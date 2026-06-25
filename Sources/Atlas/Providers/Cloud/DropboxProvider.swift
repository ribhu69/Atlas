import Foundation

// Dropbox API v2
@MainActor
final class DropboxProvider: OAuthProviderBase, @preconcurrency StorageProvider, @unchecked Sendable {
    nonisolated let id: String
    nonisolated let name: String = "Dropbox"
    nonisolated let icon: String = "tray.and.arrow.down.fill"
    nonisolated let connectionType: ConnectionType = .dropbox
    nonisolated let rootPath: String = ""
    private(set) var isConnected: Bool = false

    private let session = URLSession.shared
    private static let apiBase = URL(string: "https://api.dropboxapi.com/2")!
    private static let contentBase = URL(string: "https://content.dropboxapi.com/2")!

    init(appKey: String, appSecret: String) {
        let id = "dropbox-\(UUID().uuidString.prefix(8))"
        self.id = id
        super.init(
            clientID: appKey,
            clientSecret: appSecret,
            authURL: URL(string: "https://www.dropbox.com/oauth2/authorize")!,
            tokenURL: URL(string: "https://api.dropbox.com/oauth2/token")!,
            redirectURI: "com.atlas.files:/oauth/dropbox",
            scopes: ["files.content.read", "files.content.write", "files.metadata.read", "files.metadata.write"],
            keychainKey: "dropbox_token"
        )
    }

    func connect() async throws {
        if token == nil || token!.isExpired {
            try await authenticate()
        }
        isConnected = true
    }

    func disconnect() async {
        signOut()
        isConnected = false
    }

    func listDirectory(at path: String) async throws -> [FileItem] {
        var items: [FileItem] = []
        var cursor: String? = nil
        var hasMore = true

        let url = Self.apiBase.appendingPathComponent("files/list_folder")
        var req = try await makeRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "path": path == "" ? "" : path,
            "recursive": false,
            "limit": 2000
        ])

        let (data, _) = try await session.data(for: req)
        let response = try JSONDecoder().decode(ListFolderResponse.self, from: data)
        items.append(contentsOf: response.entries.map { dropboxItem(from: $0) })
        cursor = response.cursor
        hasMore = response.has_more

        while hasMore, let cur = cursor {
            let continueURL = Self.apiBase.appendingPathComponent("files/list_folder/continue")
            var continueReq = try await makeRequest(url: continueURL)
            continueReq.httpMethod = "POST"
            continueReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
            continueReq.httpBody = try JSONSerialization.data(withJSONObject: ["cursor": cur])
            let (data2, _) = try await session.data(for: continueReq)
            let resp2 = try JSONDecoder().decode(ListFolderResponse.self, from: data2)
            items.append(contentsOf: resp2.entries.map { dropboxItem(from: $0) })
            cursor = resp2.cursor
            hasMore = resp2.has_more
        }

        return items
    }

    func createDirectory(named name: String, in path: String) async throws -> FileItem {
        let fullPath = "\(path)/\(name)"
        let url = Self.apiBase.appendingPathComponent("files/create_folder_v2")
        var req = try await makeRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["path": fullPath, "autorename": false])
        let (data, _) = try await session.data(for: req)
        let result = try JSONDecoder().decode(CreateFolderResult.self, from: data)
        return FileItem.makeDirectory(
            name: name,
            path: fullPath,
            url: URL(string: "dropbox://\(fullPath)")!,
            providerID: id,
            modDate: Date()
        )
    }

    func rename(item: FileItem, to newName: String) async throws -> FileItem {
        let parent = (item.path as NSString).deletingLastPathComponent
        let destPath = "\(parent)/\(newName)"
        let url = Self.apiBase.appendingPathComponent("files/move_v2")
        var req = try await makeRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "from_path": item.path,
            "to_path": destPath,
            "autorename": false
        ])
        let (data, _) = try await session.data(for: req)
        let result = try JSONDecoder().decode(MoveResult.self, from: data)
        return dropboxItem(from: result.metadata)
    }

    func delete(item: FileItem) async throws {
        let url = Self.apiBase.appendingPathComponent("files/delete_v2")
        var req = try await makeRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["path": item.path])
        _ = try await session.data(for: req)
    }

    func copy(item: FileItem, to destinationPath: String, progress: @escaping @Sendable (Double) -> Void) async throws -> FileItem {
        let destPath = "\(destinationPath)/\(item.name)"
        let url = Self.apiBase.appendingPathComponent("files/copy_v2")
        var req = try await makeRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "from_path": item.path,
            "to_path": destPath,
            "autorename": false
        ])
        progress(0)
        let (data, _) = try await session.data(for: req)
        let result = try JSONDecoder().decode(CopyResult.self, from: data)
        progress(1)
        return dropboxItem(from: result.metadata)
    }

    func move(item: FileItem, to destinationPath: String) async throws -> FileItem {
        let destPath = "\(destinationPath)/\(item.name)"
        let url = Self.apiBase.appendingPathComponent("files/move_v2")
        var req = try await makeRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "from_path": item.path,
            "to_path": destPath
        ])
        let (data, _) = try await session.data(for: req)
        let result = try JSONDecoder().decode(MoveResult.self, from: data)
        return dropboxItem(from: result.metadata)
    }

    func download(item: FileItem, to localURL: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let url = Self.contentBase.appendingPathComponent("files/download")
        var req = try await makeRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("{\"path\": \"\(item.path)\"}", forHTTPHeaderField: "Dropbox-API-Arg")
        progress(0)
        let (tmpURL, _) = try await session.download(for: req)
        try FileManager.default.moveItem(at: tmpURL, to: localURL)
        progress(1)
    }

    func upload(from localURL: URL, to path: String, progress: @escaping @Sendable (Double) -> Void) async throws -> FileItem {
        let name = localURL.lastPathComponent
        let remotePath = "\(path)/\(name)"
        let url = Self.contentBase.appendingPathComponent("files/upload")
        var req = try await makeRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let apiArg = "{\"path\": \"\(remotePath)\",\"mode\": \"add\",\"autorename\": true}"
        req.setValue(apiArg, forHTTPHeaderField: "Dropbox-API-Arg")
        req.httpBody = try Data(contentsOf: localURL)
        progress(0)
        let (data, _) = try await session.data(for: req)
        let file = try JSONDecoder().decode(DropboxEntry.self, from: data)
        progress(1)
        return dropboxItem(from: file)
    }

    func exists(at path: String) async throws -> Bool {
        let url = Self.apiBase.appendingPathComponent("files/get_metadata")
        var req = try await makeRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["path": path])
        let (_, response) = try await session.data(for: req)
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    func attributes(of item: FileItem) async throws -> FileItem { item }

    // MARK: - Helpers

    private func makeRequest(url: URL) async throws -> URLRequest {
        let token = try await validAccessToken()
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return req
    }

    private func dropboxItem(from entry: DropboxEntry) -> FileItem {
        let isDir = entry.tag == "folder"
        let url = URL(string: "dropbox://\(entry.path_lower ?? entry.path_display ?? "")")!
        let path = entry.path_display ?? entry.path_lower ?? ""
        let date = entry.server_modified.flatMap { ISO8601DateFormatter().date(from: $0) }
        if isDir {
            return FileItem.makeDirectory(name: entry.name, path: path, url: url, providerID: id, modDate: date)
        } else {
            return FileItem.makeFile(name: entry.name, path: path, url: url, size: entry.size, modDate: date, providerID: id)
        }
    }

    // MARK: - Models

    private struct ListFolderResponse: Codable {
        let entries: [DropboxEntry]
        let cursor: String
        let has_more: Bool
    }

    private struct DropboxEntry: Codable {
        let name: String
        let path_lower: String?
        let path_display: String?
        let size: Int64?
        let server_modified: String?
        let content_hash: String?

        enum CodingKeys: String, CodingKey {
            case name, path_lower, path_display, size, server_modified, content_hash
            case tag = ".tag"
        }
        var tag: String = "file"

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            path_lower = try c.decodeIfPresent(String.self, forKey: .path_lower)
            path_display = try c.decodeIfPresent(String.self, forKey: .path_display)
            size = try c.decodeIfPresent(Int64.self, forKey: .size)
            server_modified = try c.decodeIfPresent(String.self, forKey: .server_modified)
            content_hash = try c.decodeIfPresent(String.self, forKey: .content_hash)
            tag = (try? c.decode(String.self, forKey: .tag)) ?? "file"
        }
    }

    private struct CreateFolderResult: Codable { let metadata: DropboxEntry }
    private struct MoveResult: Codable { let metadata: DropboxEntry }
    private struct CopyResult: Codable { let metadata: DropboxEntry }
}
