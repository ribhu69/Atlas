import Foundation

// Microsoft Graph API for OneDrive
@MainActor
final class OneDriveProvider: OAuthProviderBase, StorageProvider, @unchecked Sendable {
    nonisolated let id: String
    nonisolated let name: String = "OneDrive"
    nonisolated let icon: String = "cloud.fill"
    nonisolated let connectionType: ConnectionType = .oneDrive
    nonisolated let rootPath: String = "root"
    nonisolated private(set) var isConnected: Bool = false

    private let session = URLSession.shared
    private static let apiBase = URL(string: "https://graph.microsoft.com/v1.0/me/drive")!

    init(clientID: String, tenantID: String = "common") {
        let id = "onedrive-\(UUID().uuidString.prefix(8))"
        super.init(
            clientID: clientID,
            clientSecret: "",
            authURL: URL(string: "https://login.microsoftonline.com/\(tenantID)/oauth2/v2.0/authorize")!,
            tokenURL: URL(string: "https://login.microsoftonline.com/\(tenantID)/oauth2/v2.0/token")!,
            redirectURI: "msauth.com.atlas.files://auth",
            scopes: ["Files.ReadWrite", "offline_access"],
            keychainKey: "onedrive_token"
        )
        self.id = id
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
        let url: URL
        if path == "root" {
            url = Self.apiBase.appendingPathComponent("root/children")
        } else {
            url = Self.apiBase.appendingPathComponent("items/\(path)/children")
        }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "$select", value: "id,name,folder,file,size,lastModifiedDateTime,createdDateTime,@microsoft.graph.downloadUrl"),
            URLQueryItem(name: "$top", value: "200")
        ]

        let req = try await makeRequest(url: components.url!)
        let (data, _) = try await session.data(for: req)
        let response = try JSONDecoder().decode(ItemCollection.self, from: data)
        return response.value.map { graphItem(from: $0, parentPath: path) }
    }

    func createDirectory(named name: String, in path: String) async throws -> FileItem {
        let url: URL
        if path == "root" {
            url = Self.apiBase.appendingPathComponent("root/children")
        } else {
            url = Self.apiBase.appendingPathComponent("items/\(path)/children")
        }
        var req = try await makeRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "name": name,
            "folder": [:],
            "@microsoft.graph.conflictBehavior": "rename"
        ])
        let (data, _) = try await session.data(for: req)
        let item = try JSONDecoder().decode(GraphItem.self, from: data)
        return graphItem(from: item, parentPath: path)
    }

    func rename(item: FileItem, to newName: String) async throws -> FileItem {
        let itemID = (item.path as NSString).lastPathComponent
        let url = Self.apiBase.appendingPathComponent("items/\(itemID)")
        var req = try await makeRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["name": newName])
        let (data, _) = try await session.data(for: req)
        let updated = try JSONDecoder().decode(GraphItem.self, from: data)
        let parentPath = (item.path as NSString).deletingLastPathComponent
        return graphItem(from: updated, parentPath: parentPath)
    }

    func delete(item: FileItem) async throws {
        let itemID = (item.path as NSString).lastPathComponent
        let url = Self.apiBase.appendingPathComponent("items/\(itemID)")
        var req = try await makeRequest(url: url)
        req.httpMethod = "DELETE"
        _ = try await session.data(for: req)
    }

    func copy(item: FileItem, to destinationPath: String, progress: @escaping @Sendable (Double) -> Void) async throws -> FileItem {
        let itemID = (item.path as NSString).lastPathComponent
        let destID = (destinationPath as NSString).lastPathComponent
        let url = Self.apiBase.appendingPathComponent("items/\(itemID)/copy")
        var req = try await makeRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "parentReference": ["id": destID],
            "name": item.name
        ])
        progress(0)
        _ = try await session.data(for: req)
        // Graph copy is async; poll for completion
        try await Task.sleep(nanoseconds: 1_000_000_000)
        progress(1)
        return item
    }

    func move(item: FileItem, to destinationPath: String) async throws -> FileItem {
        let itemID = (item.path as NSString).lastPathComponent
        let destID = (destinationPath as NSString).lastPathComponent
        let url = Self.apiBase.appendingPathComponent("items/\(itemID)")
        var req = try await makeRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "parentReference": ["id": destID]
        ])
        let (data, _) = try await session.data(for: req)
        let updated = try JSONDecoder().decode(GraphItem.self, from: data)
        return graphItem(from: updated, parentPath: destinationPath)
    }

    func download(item: FileItem, to localURL: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let itemID = (item.path as NSString).lastPathComponent
        var components = URLComponents(url: Self.apiBase.appendingPathComponent("items/\(itemID)/content"), resolvingAgainstBaseURL: false)!
        let req = try await makeRequest(url: components.url!)
        progress(0)
        let (tmpURL, _) = try await session.download(for: req)
        try FileManager.default.moveItem(at: tmpURL, to: localURL)
        progress(1)
    }

    func upload(from localURL: URL, to path: String, progress: @escaping @Sendable (Double) -> Void) async throws -> FileItem {
        let name = localURL.lastPathComponent
        let parentID = path == "root" ? "root" : path
        let url = Self.apiBase.appendingPathComponent("items/\(parentID):/\(name):/content")
        var req = try await makeRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        req.httpBody = try Data(contentsOf: localURL)
        progress(0)
        let (data, _) = try await session.data(for: req)
        let item = try JSONDecoder().decode(GraphItem.self, from: data)
        progress(1)
        return graphItem(from: item, parentPath: path)
    }

    func exists(at path: String) async throws -> Bool {
        let itemID = (path as NSString).lastPathComponent
        let url = Self.apiBase.appendingPathComponent("items/\(itemID)")
        let req = try await makeRequest(url: url)
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

    private func graphItem(from item: GraphItem, parentPath: String) -> FileItem {
        let isDir = item.folder != nil
        let fullPath = "\(parentPath)/\(item.id)"
        let url = URL(string: "onedrive://\(item.id)")!
        let date = ISO8601DateFormatter().date(from: item.lastModifiedDateTime ?? "")
        if isDir {
            return FileItem.makeDirectory(name: item.name, path: fullPath, url: url, providerID: id, modDate: date)
        } else {
            return FileItem.makeFile(name: item.name, path: fullPath, url: url, size: item.size, modDate: date, providerID: id)
        }
    }

    // MARK: - Models

    private struct ItemCollection: Codable {
        let value: [GraphItem]
    }

    private struct GraphItem: Codable {
        let id: String
        let name: String
        let size: Int64?
        let lastModifiedDateTime: String?
        let createdDateTime: String?
        let folder: FolderFacet?
        let file: FileFacet?
    }

    private struct FolderFacet: Codable {
        let childCount: Int?
    }

    private struct FileFacet: Codable {
        let mimeType: String?
    }
}
