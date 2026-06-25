import Foundation

// Google Drive REST API v3
@MainActor
final class GoogleDriveProvider: OAuthProviderBase, StorageProvider, @unchecked Sendable {
    nonisolated let id: String
    nonisolated let name: String = "Google Drive"
    nonisolated let icon: String = "arrow.triangle.2.circlepath.circle.fill"
    nonisolated let connectionType: ConnectionType = .googleDrive
    nonisolated let rootPath: String = "root"
    nonisolated private(set) var isConnected: Bool = false

    private let providerIDValue: String
    private let session = URLSession.shared
    private static let apiBase = URL(string: "https://www.googleapis.com/drive/v3")!
    private static let uploadBase = URL(string: "https://www.googleapis.com/upload/drive/v3")!

    init(clientID: String, clientSecret: String) {
        let id = "googledrive-\(UUID().uuidString.prefix(8))"
        self.providerIDValue = id
        super.init(
            clientID: clientID,
            clientSecret: clientSecret,
            authURL: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
            tokenURL: URL(string: "https://oauth2.googleapis.com/token")!,
            redirectURI: "com.atlas.files:/oauth/google",
            scopes: ["https://www.googleapis.com/auth/drive"],
            keychainKey: "google_drive_token"
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
        let parentID = path == "root" ? "root" : path
        var items: [FileItem] = []
        var pageToken: String? = nil

        repeat {
            var components = URLComponents(url: Self.apiBase.appendingPathComponent("files"), resolvingAgainstBaseURL: false)!
            var queryItems = [
                URLQueryItem(name: "q", value: "'\(parentID)' in parents and trashed = false"),
                URLQueryItem(name: "fields", value: "nextPageToken,files(id,name,mimeType,size,modifiedTime,createdTime,parents,md5Checksum)"),
                URLQueryItem(name: "pageSize", value: "200"),
                URLQueryItem(name: "orderBy", value: "folder,name"),
            ]
            if let pt = pageToken { queryItems.append(URLQueryItem(name: "pageToken", value: pt)) }
            components.queryItems = queryItems

            let req = try await makeRequest(url: components.url!)
            let (data, _) = try await session.data(for: req)
            let response = try JSONDecoder().decode(FileListResponse.self, from: data)
            items.append(contentsOf: response.files.map { driveItem(from: $0, parentPath: path) })
            pageToken = response.nextPageToken
        } while pageToken != nil

        return items
    }

    func createDirectory(named name: String, in path: String) async throws -> FileItem {
        let url = Self.apiBase.appendingPathComponent("files")
        var req = try await makeRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["name": name, "mimeType": "application/vnd.google-apps.folder", "parents": [path]]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await session.data(for: req)
        let file = try JSONDecoder().decode(DriveFile.self, from: data)
        let fullPath = "\(path)/\(file.id)"
        return FileItem.makeDirectory(name: name, path: fullPath, url: URL(string: "gdrive://\(file.id)")!, providerID: id, modDate: Date())
    }

    func rename(item: FileItem, to newName: String) async throws -> FileItem {
        let fileID = (item.path as NSString).lastPathComponent
        let url = Self.apiBase.appendingPathComponent("files/\(fileID)")
        var req = try await makeRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["name": newName])
        let (data, _) = try await session.data(for: req)
        let file = try JSONDecoder().decode(DriveFile.self, from: data)
        let parentPath = (item.path as NSString).deletingLastPathComponent
        return driveItem(from: file, parentPath: parentPath)
    }

    func delete(item: FileItem) async throws {
        let fileID = (item.path as NSString).lastPathComponent
        let url = Self.apiBase.appendingPathComponent("files/\(fileID)")
        var req = try await makeRequest(url: url)
        req.httpMethod = "DELETE"
        _ = try await session.data(for: req)
    }

    func copy(item: FileItem, to destinationPath: String, progress: @escaping @Sendable (Double) -> Void) async throws -> FileItem {
        let fileID = (item.path as NSString).lastPathComponent
        let destID = (destinationPath as NSString).lastPathComponent
        let url = Self.apiBase.appendingPathComponent("files/\(fileID)/copy")
        var req = try await makeRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["parents": [destID]])
        progress(0)
        let (data, _) = try await session.data(for: req)
        let file = try JSONDecoder().decode(DriveFile.self, from: data)
        progress(1)
        return driveItem(from: file, parentPath: destinationPath)
    }

    func move(item: FileItem, to destinationPath: String) async throws -> FileItem {
        let fileID = (item.path as NSString).lastPathComponent
        let currentParent = (item.path as NSString).deletingLastPathComponent
        let currentParentID = (currentParent as NSString).lastPathComponent
        let destID = (destinationPath as NSString).lastPathComponent

        var components = URLComponents(url: Self.apiBase.appendingPathComponent("files/\(fileID)"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "addParents", value: destID),
            URLQueryItem(name: "removeParents", value: currentParentID),
            URLQueryItem(name: "fields", value: "id,name,mimeType,size,modifiedTime")
        ]
        var req = try await makeRequest(url: components.url!)
        req.httpMethod = "PATCH"
        let (data, _) = try await session.data(for: req)
        let file = try JSONDecoder().decode(DriveFile.self, from: data)
        return driveItem(from: file, parentPath: destinationPath)
    }

    func download(item: FileItem, to localURL: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let fileID = (item.path as NSString).lastPathComponent
        var components = URLComponents(url: Self.apiBase.appendingPathComponent("files/\(fileID)"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "alt", value: "media")]
        let req = try await makeRequest(url: components.url!)
        progress(0)
        let (url, _) = try await session.download(for: req)
        try FileManager.default.moveItem(at: url, to: localURL)
        progress(1)
    }

    func upload(from localURL: URL, to path: String, progress: @escaping @Sendable (Double) -> Void) async throws -> FileItem {
        let name = localURL.lastPathComponent
        let parentID = (path as NSString).lastPathComponent
        let fileData = try Data(contentsOf: localURL)
        let mimeType = UTType(filenameExtension: localURL.pathExtension)?.preferredMIMEType ?? "application/octet-stream"

        let url = Self.uploadBase.appendingPathComponent("files").appendingPathComponent("?uploadType=multipart")
        var req = try await makeRequest(url: url)
        req.httpMethod = "POST"

        let metadata = ["name": name, "parents": [parentID]] as [String: Any]
        let metaData = try JSONSerialization.data(withJSONObject: metadata)
        let boundary = "atlas_boundary_\(UUID().uuidString)"
        req.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
        body.append(metaData)
        body.append("\r\n--\(boundary)\r\nContent-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--".data(using: .utf8)!)
        req.httpBody = body

        progress(0)
        let (data, _) = try await session.data(for: req)
        let file = try JSONDecoder().decode(DriveFile.self, from: data)
        progress(1)
        return driveItem(from: file, parentPath: path)
    }

    func exists(at path: String) async throws -> Bool {
        let fileID = (path as NSString).lastPathComponent
        let url = Self.apiBase.appendingPathComponent("files/\(fileID)")
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

    private func driveItem(from file: DriveFile, parentPath: String) -> FileItem {
        let isDir = file.mimeType == "application/vnd.google-apps.folder"
        let fullPath = "\(parentPath)/\(file.id)"
        let url = URL(string: "gdrive://\(file.id)")!
        let date = ISO8601DateFormatter().date(from: file.modifiedTime ?? "")

        if isDir {
            return FileItem.makeDirectory(name: file.name, path: fullPath, url: url, providerID: id, modDate: date)
        } else {
            return FileItem.makeFile(name: file.name, path: fullPath, url: url, size: Int64(file.size ?? "0"), modDate: date, providerID: id)
        }
    }

    // MARK: - Response Models

    private struct FileListResponse: Codable {
        let files: [DriveFile]
        let nextPageToken: String?
    }

    private struct DriveFile: Codable {
        let id: String
        let name: String
        let mimeType: String
        let size: String?
        let modifiedTime: String?
        let createdTime: String?
    }
}
