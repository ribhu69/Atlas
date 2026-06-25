import Foundation

enum ProviderError: LocalizedError, Sendable {
    case notConnected
    case authenticationFailed(String)
    case permissionDenied(String)
    case fileNotFound(String)
    case alreadyExists(String)
    case networkError(String)
    case operationFailed(String)
    case unsupported(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .notConnected:                return "Not connected to server"
        case .authenticationFailed(let m): return "Authentication failed: \(m)"
        case .permissionDenied(let p):     return "Permission denied: \(p)"
        case .fileNotFound(let p):         return "File not found: \(p)"
        case .alreadyExists(let p):        return "Already exists: \(p)"
        case .networkError(let m):         return "Network error: \(m)"
        case .operationFailed(let m):      return "Operation failed: \(m)"
        case .unsupported(let m):          return "Unsupported: \(m)"
        case .cancelled:                   return "Operation cancelled"
        }
    }
}

enum ConflictResolution: Sendable {
    case replace
    case rename(String)
    case skip
}

protocol StorageProvider: AnyObject, Sendable {
    var id: String { get }
    var name: String { get }
    var icon: String { get }
    var connectionType: ConnectionType { get }
    var isConnected: Bool { get }
    var rootPath: String { get }
    var supportsTrash: Bool { get }

    func connect() async throws
    func disconnect() async

    func listDirectory(at path: String) async throws -> [FileItem]
    func createDirectory(named name: String, in path: String) async throws -> FileItem
    func rename(item: FileItem, to newName: String) async throws -> FileItem
    func delete(item: FileItem) async throws
    func trash(item: FileItem) async throws

    func copy(item: FileItem, to destinationPath: String, progress: @escaping @Sendable (Double) -> Void) async throws -> FileItem
    func move(item: FileItem, to destinationPath: String) async throws -> FileItem

    func download(item: FileItem, to localURL: URL, progress: @escaping @Sendable (Double) -> Void) async throws
    func upload(from localURL: URL, to path: String, progress: @escaping @Sendable (Double) -> Void) async throws -> FileItem

    func exists(at path: String) async throws -> Bool
    func attributes(of item: FileItem) async throws -> FileItem
    func search(query: String, in path: String) async throws -> [FileItem]
    func freeDiskSpace() async throws -> Int64?
    func totalDiskSpace() async throws -> Int64?
}

extension StorageProvider {
    var supportsTrash: Bool { false }

    func trash(item: FileItem) async throws {
        try await delete(item: item)
    }

    func search(query: String, in path: String) async throws -> [FileItem] {
        let items = try await listDirectory(at: path)
        return items.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    func freeDiskSpace() async throws -> Int64? { nil }
    func totalDiskSpace() async throws -> Int64? { nil }
}

enum SortOption: String, CaseIterable, Sendable {
    case nameAscending = "Name (A-Z)"
    case nameDescending = "Name (Z-A)"
    case dateModifiedNewest = "Date Modified (Newest)"
    case dateModifiedOldest = "Date Modified (Oldest)"
    case sizeSmallest = "Size (Smallest)"
    case sizeLargest = "Size (Largest)"
    case typeAscending = "Type (A-Z)"

    var systemImage: String {
        switch self {
        case .nameAscending, .nameDescending:       return "textformat.abc"
        case .dateModifiedNewest, .dateModifiedOldest: return "calendar"
        case .sizeSmallest, .sizeLargest:           return "arrow.up.arrow.down"
        case .typeAscending:                        return "square.grid.2x2"
        }
    }
}

func sortFileItems(_ items: [FileItem], by option: SortOption, foldersFirst: Bool = true) -> [FileItem] {
    var folders = items.filter { $0.isDirectory }
    var files = items.filter { !$0.isDirectory }

    let sort: (FileItem, FileItem) -> Bool = { a, b in
        switch option {
        case .nameAscending:
            return a.name.localizedCompare(b.name) == .orderedAscending
        case .nameDescending:
            return a.name.localizedCompare(b.name) == .orderedDescending
        case .dateModifiedNewest:
            return (a.modificationDate ?? .distantPast) > (b.modificationDate ?? .distantPast)
        case .dateModifiedOldest:
            return (a.modificationDate ?? .distantPast) < (b.modificationDate ?? .distantPast)
        case .sizeSmallest:
            return (a.size ?? 0) < (b.size ?? 0)
        case .sizeLargest:
            return (a.size ?? 0) > (b.size ?? 0)
        case .typeAscending:
            return a.fileExtension.localizedCompare(b.fileExtension) == .orderedAscending
        }
    }

    if foldersFirst {
        folders.sort(by: sort)
        files.sort(by: sort)
        return folders + files
    } else {
        return (folders + files).sorted(by: sort)
    }
}
