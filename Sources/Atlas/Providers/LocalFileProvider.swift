import Foundation

final class LocalFileProvider: StorageProvider, @unchecked Sendable {
    let id: String = "local"
    let name: String = "On My iPhone"
    let icon: String = "iphone"
    let connectionType: ConnectionType = .ftp // placeholder; local doesn't use ConnectionType
    let isConnected: Bool = true
    let rootPath: String
    let supportsTrash: Bool = true

    private let fm = FileManager.default
    private let queue = DispatchQueue(label: "local.provider", qos: .userInitiated, attributes: .concurrent)

    // Whether this instance holds a security-scoped URL that needs start/stop
    private let isSecurityScoped: Bool

    init() {
        rootPath = Self.documentsURL.path
        isSecurityScoped = false
    }

    init(rootPath: String, securityScoped: Bool = false) {
        self.rootPath = rootPath
        isSecurityScoped = securityScoped
    }

    static var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    func connect() async throws {}
    func disconnect() async {}

    func listDirectory(at path: String) async throws -> [FileItem] {
        let url = URL(fileURLWithPath: path)
        let accessing = isSecurityScoped && url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let keys: [URLResourceKey] = [
            .nameKey, .fileSizeKey, .contentModificationDateKey,
            .creationDateKey, .isDirectoryKey, .isSymbolicLinkKey,
            .isHiddenKey, .fileSecurityKey, .totalFileSizeKey
        ]
        let contents = try fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsSubdirectoryDescendants]
        )
        return contents.compactMap { fileURL in
            makeFileItem(from: fileURL)
        }
    }

    func createDirectory(named name: String, in path: String) async throws -> FileItem {
        let url = URL(fileURLWithPath: path).appendingPathComponent(name)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return FileItem.makeDirectory(
            name: name,
            path: url.path,
            url: url,
            providerID: id,
            modDate: Date()
        )
    }

    func rename(item: FileItem, to newName: String) async throws -> FileItem {
        let destURL = item.url.deletingLastPathComponent().appendingPathComponent(newName)
        try fm.moveItem(at: item.url, to: destURL)
        return makeFileItem(from: destURL) ?? item
    }

    func delete(item: FileItem) async throws {
        try fm.removeItem(at: item.url)
    }

    func trash(item: FileItem) async throws {
        var resultURL: NSURL?
        try fm.trashItem(at: item.url, resultingItemURL: &resultURL)
    }

    func copy(item: FileItem, to destinationPath: String, progress: @escaping @Sendable (Double) -> Void) async throws -> FileItem {
        let destURL = URL(fileURLWithPath: destinationPath).appendingPathComponent(item.name)
        progress(0)
        try fm.copyItem(at: item.url, to: destURL)
        progress(1)
        return makeFileItem(from: destURL) ?? item
    }

    func move(item: FileItem, to destinationPath: String) async throws -> FileItem {
        let destURL = URL(fileURLWithPath: destinationPath).appendingPathComponent(item.name)
        try fm.moveItem(at: item.url, to: destURL)
        return makeFileItem(from: destURL) ?? item
    }

    func download(item: FileItem, to localURL: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        progress(0)
        try fm.copyItem(at: item.url, to: localURL)
        progress(1)
    }

    func upload(from localURL: URL, to path: String, progress: @escaping @Sendable (Double) -> Void) async throws -> FileItem {
        let destURL = URL(fileURLWithPath: path).appendingPathComponent(localURL.lastPathComponent)
        progress(0)
        try fm.copyItem(at: localURL, to: destURL)
        progress(1)
        return makeFileItem(from: destURL) ?? FileItem.makeFile(
            name: localURL.lastPathComponent,
            path: destURL.path,
            url: destURL,
            size: nil,
            modDate: Date(),
            providerID: id
        )
    }

    func exists(at path: String) async throws -> Bool {
        fm.fileExists(atPath: path)
    }

    func attributes(of item: FileItem) async throws -> FileItem {
        makeFileItem(from: item.url) ?? item
    }

    func freeDiskSpace() async throws -> Int64? {
        let attrs = try fm.attributesOfFileSystem(forPath: NSHomeDirectory())
        return attrs[.systemFreeSize] as? Int64
    }

    func totalDiskSpace() async throws -> Int64? {
        let attrs = try fm.attributesOfFileSystem(forPath: NSHomeDirectory())
        return attrs[.systemSize] as? Int64
    }

    private func makeFileItem(from url: URL) -> FileItem? {
        guard let attrs = try? fm.attributesOfItem(atPath: url.path) else { return nil }
        let name = url.lastPathComponent
        let isDir = (attrs[.type] as? FileAttributeType) == .typeDirectory
        let size = attrs[.size] as? Int64
        let modDate = attrs[.modificationDate] as? Date
        let posix = attrs[.posixPermissions] as? Int ?? 0o644
        let permissions = FilePermissions.from(posixPermissions: posix)

        if isDir {
            return FileItem.makeDirectory(
                name: name,
                path: url.path,
                url: url,
                providerID: id,
                modDate: modDate
            )
        } else {
            return FileItem.makeFile(
                name: name,
                path: url.path,
                url: url,
                size: size,
                modDate: modDate,
                providerID: id,
                permissions: permissions
            )
        }
    }

    // Returns the locations shown under "On This Device" in the sidebar
    static func sidebarLocations() -> [(name: String, path: String, icon: String)] {
        let fm = FileManager.default
        let docsURL = documentsURL
        var locations: [(String, String, String)] = [
            ("On My iPhone", docsURL.path, "iphone"),
        ]
        // Show Downloads if it exists inside the sandbox
        let downloadsURL = docsURL.appendingPathComponent("Downloads")
        if (try? downloadsURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            locations.append(("Downloads", downloadsURL.path, "arrow.down.circle.fill"))
        }
        return locations
    }
}
