import Foundation

final class WebDAVProvider: StorageProvider, @unchecked Sendable {
    nonisolated let id: String
    nonisolated let name: String
    nonisolated let icon: String = "network"
    nonisolated let connectionType: ConnectionType
    nonisolated let rootPath: String
    nonisolated private(set) var isConnected: Bool = false

    private let config: ConnectionConfig
    private var session: URLSession!
    private var baseURL: URL

    init(config: ConnectionConfig) {
        self.config = config
        self.id = config.providerID()
        self.name = config.name
        self.connectionType = config.type
        self.rootPath = config.remotePath

        let scheme = config.type == .webdavs ? "https" : "http"
        let urlString = "\(scheme)://\(config.host):\(config.port)"
        self.baseURL = URL(string: urlString) ?? URL(string: "http://localhost")!

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: sessionConfig)
    }

    func connect() async throws {
        let req = try makeRequest(method: "OPTIONS", path: rootPath)
        let (_, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw ProviderError.networkError("Server returned error")
        }
        isConnected = true
    }

    func disconnect() async {
        session.invalidateAndCancel()
        isConnected = false
    }

    func listDirectory(at path: String) async throws -> [FileItem] {
        var req = try makeRequest(method: "PROPFIND", path: path)
        req.setValue("1", forHTTPHeaderField: "Depth")
        req.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        req.httpBody = propfindBody

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 207 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw ProviderError.operationFailed("PROPFIND failed with status \(code)")
        }
        return try parseMultiStatus(data: data, basePath: path)
    }

    func createDirectory(named name: String, in path: String) async throws -> FileItem {
        let fullPath = (path as NSString).appendingPathComponent(name) + "/"
        let req = try makeRequest(method: "MKCOL", path: fullPath)
        let (_, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 201 else {
            throw ProviderError.operationFailed("MKCOL failed")
        }
        let url = baseURL.appendingPathComponent(fullPath)
        return FileItem.makeDirectory(name: name, path: fullPath, url: url, providerID: id, modDate: Date())
    }

    func rename(item: FileItem, to newName: String) async throws -> FileItem {
        let destPath = (item.path as NSString).deletingLastPathComponent + "/" + newName
        var req = try makeRequest(method: "MOVE", path: item.path)
        req.setValue(baseURL.appendingPathComponent(destPath).absoluteString, forHTTPHeaderField: "Destination")
        req.setValue("F", forHTTPHeaderField: "Overwrite")
        let (_, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 201 || http.statusCode == 204 else {
            throw ProviderError.operationFailed("MOVE failed")
        }
        let destURL = baseURL.appendingPathComponent(destPath)
        return FileItem.makeFile(name: newName, path: destPath, url: destURL, size: item.size, modDate: Date(), providerID: id)
    }

    func delete(item: FileItem) async throws {
        let req = try makeRequest(method: "DELETE", path: item.path)
        let (_, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 204 || http.statusCode == 200 else {
            throw ProviderError.operationFailed("DELETE failed")
        }
    }

    func copy(item: FileItem, to destinationPath: String, progress: @escaping @Sendable (Double) -> Void) async throws -> FileItem {
        let destPath = (destinationPath as NSString).appendingPathComponent(item.name)
        var req = try makeRequest(method: "COPY", path: item.path)
        req.setValue(baseURL.appendingPathComponent(destPath).absoluteString, forHTTPHeaderField: "Destination")
        req.setValue("F", forHTTPHeaderField: "Overwrite")
        progress(0)
        let (_, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 201 || http.statusCode == 204 else {
            throw ProviderError.operationFailed("COPY failed")
        }
        progress(1)
        let destURL = baseURL.appendingPathComponent(destPath)
        return FileItem.makeFile(name: item.name, path: destPath, url: destURL, size: item.size, modDate: Date(), providerID: id)
    }

    func move(item: FileItem, to destinationPath: String) async throws -> FileItem {
        let newPath = (destinationPath as NSString).appendingPathComponent(item.name)
        var req = try makeRequest(method: "MOVE", path: item.path)
        req.setValue(baseURL.appendingPathComponent(newPath).absoluteString, forHTTPHeaderField: "Destination")
        req.setValue("F", forHTTPHeaderField: "Overwrite")
        let (_, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 201 || http.statusCode == 204 else {
            throw ProviderError.operationFailed("MOVE failed")
        }
        let destURL = baseURL.appendingPathComponent(newPath)
        return FileItem.makeFile(name: item.name, path: newPath, url: destURL, size: item.size, modDate: Date(), providerID: id)
    }

    func download(item: FileItem, to localURL: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let req = try makeRequest(method: "GET", path: item.path)
        progress(0)
        let (url, _) = try await session.download(for: req)
        try FileManager.default.moveItem(at: url, to: localURL)
        progress(1)
    }

    func upload(from localURL: URL, to path: String, progress: @escaping @Sendable (Double) -> Void) async throws -> FileItem {
        let name = localURL.lastPathComponent
        let remotePath = (path as NSString).appendingPathComponent(name)
        var req = try makeRequest(method: "PUT", path: remotePath)
        req.httpBodyStream = InputStream(url: localURL)
        let size = (try? FileManager.default.attributesOfItem(atPath: localURL.path)[.size] as? Int64) ?? 0
        req.setValue(String(size), forHTTPHeaderField: "Content-Length")
        progress(0)
        let (_, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 201 || http.statusCode == 204 else {
            throw ProviderError.operationFailed("PUT failed")
        }
        progress(1)
        let destURL = baseURL.appendingPathComponent(remotePath)
        return FileItem.makeFile(name: name, path: remotePath, url: destURL, size: size, modDate: Date(), providerID: id)
    }

    func exists(at path: String) async throws -> Bool {
        var req = try makeRequest(method: "PROPFIND", path: path)
        req.setValue("0", forHTTPHeaderField: "Depth")
        req.httpBody = propfindBody
        let (_, response) = try await session.data(for: req)
        return (response as? HTTPURLResponse)?.statusCode == 207
    }

    func attributes(of item: FileItem) async throws -> FileItem { item }

    // MARK: - Helpers

    private func makeRequest(method: String, path: String) throws -> URLRequest {
        let url = baseURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = method
        if !config.username.isEmpty {
            let cred = Data("\(config.username):\(config.password)".utf8).base64EncodedString()
            req.setValue("Basic \(cred)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    private var propfindBody: Data {
        """
        <?xml version="1.0" encoding="utf-8"?>
        <D:propfind xmlns:D="DAV:">
            <D:prop>
                <D:displayname/>
                <D:getcontentlength/>
                <D:getlastmodified/>
                <D:resourcetype/>
                <D:creationdate/>
            </D:prop>
        </D:propfind>
        """.data(using: .utf8)!
    }

    private func parseMultiStatus(data: Data, basePath: String) throws -> [FileItem] {
        let parser = WebDAVXMLParser(data: data, baseURL: baseURL, providerID: id)
        return try parser.parse(basePath: basePath)
    }
}

// MARK: - WebDAV XML Parser

private final class WebDAVXMLParser: NSObject, XMLParserDelegate {
    private let data: Data
    private let baseURL: URL
    private let providerID: String

    private var items: [FileItem] = []
    private var currentHref: String = ""
    private var currentName: String = ""
    private var currentSize: Int64?
    private var currentModDate: Date?
    private var currentIsDir: Bool = false
    private var isFirstResponse: Bool = true
    private var currentElement: String = ""
    private var basePath: String = ""
    private var isCapturing: Bool = false

    private let rfc1123Formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
        f.timeZone = TimeZone(identifier: "GMT")
        return f
    }()

    init(data: Data, baseURL: URL, providerID: String) {
        self.data = data
        self.baseURL = baseURL
        self.providerID = providerID
    }

    func parse(basePath: String) throws -> [FileItem] {
        self.basePath = basePath
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return items
    }

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        currentElement = element
        switch element {
        case "D:response", "response":
            currentHref = ""
            currentName = ""
            currentSize = nil
            currentModDate = nil
            currentIsDir = false
        case "D:href", "href",
             "D:displayname", "displayname",
             "D:getcontentlength", "getcontentlength",
             "D:getlastmodified", "getlastmodified":
            isCapturing = true
        case "D:collection", "collection":
            currentIsDir = true
        default:
            isCapturing = false
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard isCapturing else { return }
        let s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return }
        switch currentElement {
        case "D:href", "href":
            currentHref = s
        case "D:displayname", "displayname":
            currentName = s
        case "D:getcontentlength", "getcontentlength":
            currentSize = Int64(s)
        case "D:getlastmodified", "getlastmodified":
            currentModDate = rfc1123Formatter.date(from: s)
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        isCapturing = false
        guard element == "D:response" || element == "response" else { return }
        defer { isFirstResponse = false }
        if isFirstResponse { return } // Skip the collection itself

        var path = currentHref
        if path.hasPrefix(baseURL.path) {
            path = String(path.dropFirst(baseURL.path.count))
        }
        let name = currentName.isEmpty ? (path as NSString).lastPathComponent : currentName
        guard !name.isEmpty, name != "." else { return }

        let url = baseURL.appendingPathComponent(path)
        if currentIsDir {
            items.append(FileItem.makeDirectory(name: name, path: path, url: url, providerID: providerID, modDate: currentModDate))
        } else {
            items.append(FileItem.makeFile(name: name, path: path, url: url, size: currentSize, modDate: currentModDate, providerID: providerID))
        }
    }
}
