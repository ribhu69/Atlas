import Foundation

final class iCloudProvider: StorageProvider, @unchecked Sendable {
    nonisolated let id: String = "icloud"
    nonisolated let name: String = "iCloud Drive"
    nonisolated let icon: String = "icloud.fill"
    nonisolated let connectionType: ConnectionType = .iCloud
    nonisolated let rootPath: String
    private(set) var isConnected: Bool = false
    nonisolated let supportsTrash: Bool = true

    private let fm = FileManager.default
    private var metadataQuery: NSMetadataQuery?
    private var iCloudRoot: URL?

    init() {
        if let root = FileManager.default.url(forUbiquityContainerIdentifier: nil) {
            let docs = root.appendingPathComponent("Documents")
            self.rootPath = docs.path
            self.iCloudRoot = docs
        } else {
            self.rootPath = NSHomeDirectory() + "/Library/Mobile Documents"
            self.iCloudRoot = URL(fileURLWithPath: rootPath)
        }
    }

    func connect() async throws {
        guard fm.ubiquityIdentityToken != nil else {
            throw ProviderError.authenticationFailed("iCloud is not available. Make sure you're signed into iCloud.")
        }
        // Ensure iCloud container exists
        if let root = iCloudRoot {
            try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        }
        isConnected = true
    }

    func disconnect() async {
        isConnected = false
    }

    func listDirectory(at path: String) async throws -> [FileItem] {
        let url = URL(fileURLWithPath: path)
        // Trigger download of placeholders
        try? fm.startDownloadingUbiquitousItem(at: url)

        let keys: [URLResourceKey] = [
            .nameKey, .fileSizeKey, .contentModificationDateKey,
            .creationDateKey, .isDirectoryKey, .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey, .ubiquitousItemIsDownloadingKey,
            .ubiquitousItemIsUploadedKey
        ]
        let contents = try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: .skipsSubdirectoryDescendants)
        return contents.compactMap { makeItem(from: $0) }
    }

    func createDirectory(named name: String, in path: String) async throws -> FileItem {
        let url = URL(fileURLWithPath: path).appendingPathComponent(name)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return FileItem.makeDirectory(name: name, path: url.path, url: url, providerID: id, modDate: Date())
    }

    func rename(item: FileItem, to newName: String) async throws -> FileItem {
        let dest = item.url.deletingLastPathComponent().appendingPathComponent(newName)
        let coordinator = NSFileCoordinator()
        var coordError: NSError?
        var moveError: Error?

        coordinator.coordinate(writingItemAt: item.url, options: .forMoving, writingItemAt: dest, options: .forReplacing, error: &coordError) { src, dst in
            do {
                coordinator.item(at: src, willMoveTo: dst)
                try self.fm.moveItem(at: src, to: dst)
                coordinator.item(at: src, didMoveTo: dst)
            } catch {
                moveError = error
            }
        }
        if let err = coordError ?? moveError {
            throw ProviderError.operationFailed(err.localizedDescription)
        }
        return makeItem(from: dest) ?? item
    }

    func delete(item: FileItem) async throws {
        let coordinator = NSFileCoordinator()
        var coordError: NSError?
        var deleteError: Error?
        coordinator.coordinate(writingItemAt: item.url, options: .forDeleting, error: &coordError) { url in
            do { try self.fm.removeItem(at: url) }
            catch { deleteError = error }
        }
        if let err = coordError ?? deleteError { throw ProviderError.operationFailed(err.localizedDescription) }
    }

    func trash(item: FileItem) async throws {
        var resultURL: NSURL?
        try fm.trashItem(at: item.url, resultingItemURL: &resultURL)
    }

    func copy(item: FileItem, to destinationPath: String, progress: @escaping @Sendable (Double) -> Void) async throws -> FileItem {
        let dest = URL(fileURLWithPath: destinationPath).appendingPathComponent(item.name)
        progress(0)
        let coordinator = NSFileCoordinator()
        var coordError: NSError?
        var copyError: Error?
        coordinator.coordinate(readingItemAt: item.url, options: [], writingItemAt: dest, options: .forReplacing, error: &coordError) { src, dst in
            do { try self.fm.copyItem(at: src, to: dst) }
            catch { copyError = error }
        }
        if let err = coordError ?? copyError { throw ProviderError.operationFailed(err.localizedDescription) }
        progress(1)
        return makeItem(from: dest) ?? item
    }

    func move(item: FileItem, to destinationPath: String) async throws -> FileItem {
        let dest = URL(fileURLWithPath: destinationPath).appendingPathComponent(item.name)
        let coordinator = NSFileCoordinator()
        var coordError: NSError?
        var moveError: Error?
        coordinator.coordinate(writingItemAt: item.url, options: .forMoving, writingItemAt: dest, options: .forReplacing, error: &coordError) { src, dst in
            do {
                coordinator.item(at: src, willMoveTo: dst)
                try self.fm.moveItem(at: src, to: dst)
                coordinator.item(at: src, didMoveTo: dst)
            } catch {
                moveError = error
            }
        }
        if let err = coordError ?? moveError { throw ProviderError.operationFailed(err.localizedDescription) }
        return makeItem(from: dest) ?? item
    }

    func download(item: FileItem, to localURL: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        // Ensure file is downloaded from iCloud
        try fm.startDownloadingUbiquitousItem(at: item.url)
        // Wait until downloaded
        var attempts = 0
        while attempts < 30 {
            if let status = try? item.url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus,
               status == .current { break }
            try await Task.sleep(nanoseconds: 500_000_000)
            attempts += 1
            progress(Double(attempts) / 30.0)
        }
        try fm.copyItem(at: item.url, to: localURL)
        progress(1)
    }

    func upload(from localURL: URL, to path: String, progress: @escaping @Sendable (Double) -> Void) async throws -> FileItem {
        let dest = URL(fileURLWithPath: path).appendingPathComponent(localURL.lastPathComponent)
        progress(0)
        try fm.copyItem(at: localURL, to: dest)
        progress(1)
        return makeItem(from: dest) ?? FileItem.makeFile(
            name: localURL.lastPathComponent,
            path: dest.path,
            url: dest,
            size: nil,
            modDate: Date(),
            providerID: id
        )
    }

    func exists(at path: String) async throws -> Bool {
        fm.fileExists(atPath: path)
    }

    func attributes(of item: FileItem) async throws -> FileItem {
        makeItem(from: item.url) ?? item
    }

    func search(query: String, in path: String) async throws -> [FileItem] {
        let metaQuery = NSMetadataQuery()
        metaQuery.predicate = NSPredicate(format: "%K CONTAINS[cd] %@", NSMetadataItemFSNameKey, query)
        metaQuery.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]

        return try await withCheckedThrowingContinuation { continuation in
            var observer: NSObjectProtocol?
            observer = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: metaQuery, queue: .main) { _ in
                metaQuery.stop()
                var results: [FileItem] = []
                for i in 0..<metaQuery.resultCount {
                    if let item = metaQuery.result(at: i) as? NSMetadataItem,
                       let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL {
                        if let fileItem = self.makeItem(from: url) {
                            results.append(fileItem)
                        }
                    }
                }
                if let obs = observer { NotificationCenter.default.removeObserver(obs) }
                continuation.resume(returning: results)
            }
            metaQuery.start()
        }
    }

    private func makeItem(from url: URL) -> FileItem? {
        guard let attrs = try? fm.attributesOfItem(atPath: url.path) else { return nil }
        let name = url.lastPathComponent
        guard !name.isEmpty else { return nil }
        let isDir = (attrs[.type] as? FileAttributeType) == .typeDirectory
        let size = attrs[.size] as? Int64
        let modDate = attrs[.modificationDate] as? Date

        if isDir {
            return FileItem.makeDirectory(name: name, path: url.path, url: url, providerID: id, modDate: modDate)
        } else {
            return FileItem.makeFile(name: name, path: url.path, url: url, size: size, modDate: modDate, providerID: id)
        }
    }
}
