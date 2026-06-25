import Foundation
import BackgroundTasks

// MARK: - Operation Types

enum FileOperationKind: Sendable {
    case copy(source: FileItem, destinationPath: String)
    case move(source: FileItem, destinationPath: String)
    case delete(items: [FileItem])
    case rename(item: FileItem, newName: String)
    case createDirectory(name: String, path: String)
    case upload(localURL: URL, destinationPath: String)
    case download(item: FileItem, localURL: URL)
    case compress(items: [FileItem], destinationPath: String, archiveName: String)
    case decompress(item: FileItem, destinationPath: String)

    var description: String {
        switch self {
        case .copy(let src, _):         return "Copying \(src.name)"
        case .move(let src, _):         return "Moving \(src.name)"
        case .delete(let items):        return "Deleting \(items.count) item(s)"
        case .rename(let item, let n):  return "Renaming \(item.name) to \(n)"
        case .createDirectory(let n, _): return "Creating folder \(n)"
        case .upload(let url, _):       return "Uploading \(url.lastPathComponent)"
        case .download(let item, _):    return "Downloading \(item.name)"
        case .compress(_, _, let n):    return "Compressing to \(n)"
        case .decompress(let item, _):  return "Extracting \(item.name)"
        }
    }
}

enum FileOperationStatus: Sendable {
    case pending
    case running
    case completed
    case failed(Error)
    case cancelled

    var isFinished: Bool {
        switch self {
        case .completed, .failed, .cancelled: return true
        default: return false
        }
    }
}

@Observable
final class FileOperation: Identifiable, @unchecked Sendable {
    let id = UUID()
    let kind: FileOperationKind
    let provider: any StorageProvider

    var status: FileOperationStatus = .pending
    var progress: Double = 0
    var result: FileItem?
    var errorMessage: String?
    var startedAt: Date?
    var completedAt: Date?

    var description: String { kind.description }
    var isActive: Bool {
        if case .running = status { return true }
        if case .pending = status { return true }
        return false
    }

    private var _task: Task<Void, Never>?

    init(kind: FileOperationKind, provider: any StorageProvider) {
        self.kind = kind
        self.provider = provider
    }

    func cancel() {
        _task?.cancel()
        status = .cancelled
    }

    func run(conflictHandler: @escaping @Sendable (String) async -> ConflictResolution) async {
        guard case .pending = status else { return }
        status = .running
        startedAt = Date()
        _task = Task {
            do {
                try await execute(conflictHandler: conflictHandler)
                await MainActor.run {
                    self.status = .completed
                    self.progress = 1.0
                    self.completedAt = Date()
                }
            } catch is CancellationError {
                await MainActor.run { self.status = .cancelled }
            } catch {
                await MainActor.run {
                    self.status = .failed(error)
                    self.errorMessage = error.localizedDescription
                    self.completedAt = Date()
                }
            }
        }
        await _task?.value
    }

    private func execute(conflictHandler: @escaping @Sendable (String) async -> ConflictResolution) async throws {
        let progressCallback: @Sendable (Double) -> Void = { [weak self] p in
            Task { @MainActor [weak self] in self?.progress = p }
        }

        switch kind {
        case .copy(let source, let destPath):
            let exists = (try? await provider.exists(at: "\(destPath)/\(source.name)")) ?? false
            if exists {
                let resolution = await conflictHandler(source.name)
                switch resolution {
                case .skip: return
                case .rename(let newName):
                    let renamedSource = try await provider.rename(item: source, to: newName)
                    result = try await provider.copy(item: renamedSource, to: destPath, progress: progressCallback)
                case .replace:
                    result = try await provider.copy(item: source, to: destPath, progress: progressCallback)
                }
            } else {
                result = try await provider.copy(item: source, to: destPath, progress: progressCallback)
            }

        case .move(let source, let destPath):
            result = try await provider.move(item: source, to: destPath)
            progress = 1

        case .delete(let items):
            let total = Double(items.count)
            for (i, item) in items.enumerated() {
                try await provider.delete(item: item)
                progressCallback(Double(i + 1) / total)
            }

        case .rename(let item, let newName):
            result = try await provider.rename(item: item, to: newName)
            progress = 1

        case .createDirectory(let name, let path):
            result = try await provider.createDirectory(named: name, in: path)
            progress = 1

        case .upload(let localURL, let destPath):
            result = try await provider.upload(from: localURL, to: destPath, progress: progressCallback)

        case .download(let item, let localURL):
            try await provider.download(item: item, to: localURL, progress: progressCallback)

        case .compress(let items, let destPath, let name):
            let handler = ArchiveHandler()
            let archiveURL = try await handler.compress(items: items, archiveName: name, progress: progressCallback)
            result = try await provider.upload(from: archiveURL, to: destPath, progress: { _ in })
            try? FileManager.default.removeItem(at: archiveURL)

        case .decompress(let item, let destPath):
            let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(item.name)
            try await provider.download(item: item, to: tmpURL, progress: { p in progressCallback(p * 0.5) })
            let handler = ArchiveHandler()
            try await handler.decompress(archiveURL: tmpURL, to: URL(fileURLWithPath: destPath), progress: { p in progressCallback(0.5 + p * 0.5) })
            try? FileManager.default.removeItem(at: tmpURL)
        }
    }
}

// MARK: - Engine

@Observable
@MainActor
final class FileOperationEngine {
    static let shared = FileOperationEngine()

    var operations: [FileOperation] = []
    var activeCount: Int { operations.filter { $0.isActive }.count }

    private let maxConcurrent = 3
    private var running = 0

    var conflictHandler: (@Sendable (String) async -> ConflictResolution)?

    func enqueue(_ operation: FileOperation) {
        operations.append(operation)
        processQueue()
    }

    func enqueueAll(_ ops: [FileOperation]) {
        operations.append(contentsOf: ops)
        processQueue()
    }

    func cancel(_ operation: FileOperation) {
        operation.cancel()
    }

    func cancelAll() {
        operations.filter { $0.isActive }.forEach { $0.cancel() }
    }

    func clearCompleted() {
        operations.removeAll { $0.status.isFinished }
    }

    private func processQueue() {
        let pending = operations.filter {
            if case .pending = $0.status { return true }
            return false
        }
        let canStart = min(maxConcurrent - running, pending.count)
        guard canStart > 0 else { return }

        for op in pending.prefix(canStart) {
            running += 1
            Task {
                let handler = self.conflictHandler ?? { _ in .replace }
                await op.run(conflictHandler: handler)
                await MainActor.run {
                    self.running -= 1
                    self.processQueue()
                }
            }
        }
    }

    // Convenience factory methods
    func copy(items: [FileItem], to path: String, using provider: any StorageProvider) {
        let ops = items.map { FileOperation(kind: .copy(source: $0, destinationPath: path), provider: provider) }
        enqueueAll(ops)
    }

    func move(items: [FileItem], to path: String, using provider: any StorageProvider) {
        let ops = items.map { FileOperation(kind: .move(source: $0, destinationPath: path), provider: provider) }
        enqueueAll(ops)
    }

    func delete(items: [FileItem], using provider: any StorageProvider) {
        let op = FileOperation(kind: .delete(items: items), provider: provider)
        enqueue(op)
    }

    func download(items: [FileItem], using provider: any StorageProvider) {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let ops = items.map {
            FileOperation(kind: .download(item: $0, localURL: downloads.appendingPathComponent($0.name)), provider: provider)
        }
        enqueueAll(ops)
    }
}
