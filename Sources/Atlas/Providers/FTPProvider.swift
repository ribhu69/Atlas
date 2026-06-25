import Foundation
import Network

// Full FTP/FTPS client built on NWConnection
actor FTPProvider: StorageProvider {
    nonisolated let id: String
    nonisolated let name: String
    nonisolated let icon: String = "server.rack"
    nonisolated let connectionType: ConnectionType
    nonisolated let rootPath: String

    private let config: ConnectionConfig
    private var controlConnection: NWConnection?
    private var _isConnected: Bool = false

    nonisolated var isConnected: Bool {
        // Actor isolation workaround for protocol conformance
        false // Updated via async accessor; use isConnectedAsync
    }

    func isConnectedAsync() -> Bool { _isConnected }

    init(config: ConnectionConfig) {
        self.config = config
        self.id = config.providerID()
        self.name = config.name
        self.connectionType = config.type
        self.rootPath = config.remotePath
    }

    // MARK: - Connection

    func connect() async throws {
        let host = NWEndpoint.Host(config.host)
        let port = NWEndpoint.Port(rawValue: UInt16(config.port)) ?? 21
        let params = config.type == .ftps ? NWParameters.tls : NWParameters.tcp
        let conn = NWConnection(host: host, port: port, using: params)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    continuation.resume()
                case .failed(let err):
                    continuation.resume(throwing: ProviderError.networkError(err.localizedDescription))
                case .cancelled:
                    continuation.resume(throwing: ProviderError.cancelled)
                default:
                    break
                }
            }
            conn.start(queue: .global(qos: .userInitiated))
        }

        controlConnection = conn

        // Read server greeting (220)
        let greeting = try await readResponse()
        guard greeting.starts(with: "220") else {
            throw ProviderError.networkError("Unexpected greeting: \(greeting)")
        }

        // Authenticate
        try await sendCommand("USER \(config.username)")
        let userResp = try await readResponse()
        guard userResp.starts(with: "331") || userResp.starts(with: "230") else {
            throw ProviderError.authenticationFailed(userResp)
        }

        if userResp.starts(with: "331") {
            try await sendCommand("PASS \(config.password)")
            let passResp = try await readResponse()
            guard passResp.starts(with: "230") else {
                throw ProviderError.authenticationFailed(passResp)
            }
        }

        // Set binary mode
        try await sendCommand("TYPE I")
        _ = try await readResponse()

        // Set UTF-8 if supported
        try await sendCommand("OPTS UTF8 ON")
        _ = try await readResponse()

        _isConnected = true
    }

    func disconnect() async {
        try? await sendCommand("QUIT")
        controlConnection?.cancel()
        controlConnection = nil
        _isConnected = false
    }

    // MARK: - Directory Operations

    func listDirectory(at path: String) async throws -> [FileItem] {
        try assertConnected()
        let dataConn = try await openPassiveConnection()
        try await sendCommand("MLSD \(path)")
        let response = try await readResponse()
        guard response.starts(with: "150") || response.starts(with: "125") else {
            throw ProviderError.operationFailed("MLSD failed: \(response)")
        }
        let raw = try await readAllData(from: dataConn)
        _ = try await readResponse() // 226 Transfer complete
        let listing = String(data: raw, encoding: .utf8) ?? ""
        return parseMlsd(listing, path: path)
    }

    func createDirectory(named name: String, in path: String) async throws -> FileItem {
        try assertConnected()
        let fullPath = (path as NSString).appendingPathComponent(name)
        try await sendCommand("MKD \(fullPath)")
        let resp = try await readResponse()
        guard resp.starts(with: "257") else {
            throw ProviderError.operationFailed("MKD failed: \(resp)")
        }
        return FileItem.makeDirectory(
            name: name,
            path: fullPath,
            url: URL(string: "ftp://\(config.host)\(fullPath)") ?? URL(fileURLWithPath: fullPath),
            providerID: id,
            modDate: Date()
        )
    }

    func rename(item: FileItem, to newName: String) async throws -> FileItem {
        try assertConnected()
        let destPath = (item.path as NSString).deletingLastPathComponent + "/" + newName
        try await sendCommand("RNFR \(item.path)")
        let rnfrResp = try await readResponse()
        guard rnfrResp.starts(with: "350") else {
            throw ProviderError.operationFailed("RNFR failed: \(rnfrResp)")
        }
        try await sendCommand("RNTO \(destPath)")
        let rntoResp = try await readResponse()
        guard rntoResp.starts(with: "250") else {
            throw ProviderError.operationFailed("RNTO failed: \(rntoResp)")
        }
        let destURL = URL(string: "ftp://\(config.host)\(destPath)") ?? URL(fileURLWithPath: destPath)
        return FileItem.makeFile(
            name: newName,
            path: destPath,
            url: destURL,
            size: item.size,
            modDate: item.modificationDate,
            providerID: id
        )
    }

    func delete(item: FileItem) async throws {
        try assertConnected()
        let cmd = item.isDirectory ? "RMD \(item.path)" : "DELE \(item.path)"
        try await sendCommand(cmd)
        let resp = try await readResponse()
        guard resp.starts(with: "250") || resp.starts(with: "257") else {
            throw ProviderError.operationFailed("Delete failed: \(resp)")
        }
    }

    func trash(item: FileItem) async throws {
        try await delete(item: item)
    }

    // MARK: - File Transfer

    func copy(item: FileItem, to destinationPath: String, progress: @escaping @Sendable (Double) -> Void) async throws -> FileItem {
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(item.name)
        try await download(item: item, to: tmpURL, progress: { p in progress(p * 0.5) })
        let result = try await upload(from: tmpURL, to: destinationPath, progress: { p in progress(0.5 + p * 0.5) })
        try? FileManager.default.removeItem(at: tmpURL)
        return result
    }

    func move(item: FileItem, to destinationPath: String) async throws -> FileItem {
        let newPath = (destinationPath as NSString).appendingPathComponent(item.name)
        return try await rename(item: item, to: newPath)
    }

    func download(item: FileItem, to localURL: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        try assertConnected()
        let dataConn = try await openPassiveConnection()
        try await sendCommand("RETR \(item.path)")
        let transferResp = try await readResponse()
        guard transferResp.starts(with: "150") || transferResp.starts(with: "125") else {
            throw ProviderError.operationFailed("RETR failed: \(transferResp)")
        }
        let totalSize = item.size ?? 0
        var received: Int64 = 0
        let fileHandle = try FileHandle(forWritingTo: { () -> URL in
            FileManager.default.createFile(atPath: localURL.path, contents: nil)
            return localURL
        }())
        defer { try? fileHandle.close() }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.receiveChunked(connection: dataConn, totalSize: totalSize, received: &received, fileHandle: fileHandle, progress: progress, continuation: continuation)
        }
        _ = try await readResponse() // 226
    }

    func upload(from localURL: URL, to path: String, progress: @escaping @Sendable (Double) -> Void) async throws -> FileItem {
        try assertConnected()
        let name = localURL.lastPathComponent
        let remotePath = (path as NSString).appendingPathComponent(name)
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: localURL.path)[.size] as? Int64) ?? 0

        let dataConn = try await openPassiveConnection()
        try await sendCommand("STOR \(remotePath)")
        let resp = try await readResponse()
        guard resp.starts(with: "150") || resp.starts(with: "125") else {
            throw ProviderError.operationFailed("STOR failed: \(resp)")
        }

        guard let inputStream = InputStream(url: localURL) else {
            throw ProviderError.operationFailed("Cannot open file for reading")
        }
        inputStream.open()
        defer { inputStream.close() }

        var uploaded: Int64 = 0
        let bufferSize = 65536
        var buffer = [UInt8](repeating: 0, count: bufferSize)

        while inputStream.hasBytesAvailable {
            let read = inputStream.read(&buffer, maxLength: bufferSize)
            guard read > 0 else { break }
            let chunk = Data(buffer[0..<read])
            try await sendData(chunk, on: dataConn)
            uploaded += Int64(read)
            if fileSize > 0 { progress(Double(uploaded) / Double(fileSize)) }
        }

        dataConn.cancel()
        _ = try await readResponse() // 226

        let remoteURL = URL(string: "ftp://\(config.host)\(remotePath)") ?? URL(fileURLWithPath: remotePath)
        return FileItem.makeFile(
            name: name,
            path: remotePath,
            url: remoteURL,
            size: fileSize,
            modDate: Date(),
            providerID: id
        )
    }

    func exists(at path: String) async throws -> Bool {
        try assertConnected()
        try await sendCommand("MDTM \(path)")
        let resp = try await readResponse()
        return resp.starts(with: "213")
    }

    func attributes(of item: FileItem) async throws -> FileItem {
        item
    }

    // MARK: - Passive Mode

    private func openPassiveConnection() async throws -> NWConnection {
        try await sendCommand("EPSV")
        let epsvResp = try await readResponse()
        if epsvResp.starts(with: "229"), let port = parseEPSV(epsvResp) {
            let host = NWEndpoint.Host(config.host)
            let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) ?? 21
            return try await makeDataConnection(host: host, port: nwPort)
        }

        // Fall back to PASV
        try await sendCommand("PASV")
        let pasvResp = try await readResponse()
        guard pasvResp.starts(with: "227"),
              let (host, port) = parsePASV(pasvResp) else {
            throw ProviderError.operationFailed("PASV failed: \(pasvResp)")
        }
        return try await makeDataConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: UInt16(port)) ?? 21)
    }

    private func makeDataConnection(host: NWEndpoint.Host, port: NWEndpoint.Port) async throws -> NWConnection {
        let conn = NWConnection(host: host, port: port, using: .tcp)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    continuation.resume()
                case .failed(let err):
                    continuation.resume(throwing: ProviderError.networkError(err.localizedDescription))
                default:
                    break
                }
            }
            conn.start(queue: .global(qos: .userInitiated))
        }
        return conn
    }

    // MARK: - Low-level I/O

    private func sendCommand(_ cmd: String) async throws {
        guard let conn = controlConnection else { throw ProviderError.notConnected }
        let data = (cmd + "\r\n").data(using: .utf8)!
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            conn.send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: ProviderError.networkError(error.localizedDescription)) }
                else { continuation.resume() }
            })
        }
    }

    private func sendData(_ data: Data, on conn: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            conn.send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: ProviderError.networkError(error.localizedDescription)) }
                else { continuation.resume() }
            })
        }
    }

    private func readResponse() async throws -> String {
        guard let conn = controlConnection else { throw ProviderError.notConnected }
        return try await withCheckedThrowingContinuation { continuation in
            conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: ProviderError.networkError(error.localizedDescription))
                } else if let data, let str = String(data: data, encoding: .utf8) {
                    continuation.resume(returning: str.trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    continuation.resume(returning: "")
                }
            }
        }
    }

    private func readAllData(from conn: NWConnection) async throws -> Data {
        var allData = Data()
        while true {
            let chunk: Data? = try await withCheckedThrowingContinuation { continuation in
                conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                    if let error {
                        continuation.resume(throwing: ProviderError.networkError(error.localizedDescription))
                    } else {
                        continuation.resume(returning: isComplete ? nil : data)
                    }
                }
            }
            guard let chunk else { break }
            allData.append(chunk)
        }
        conn.cancel()
        return allData
    }

    private func receiveChunked(
        connection: NWConnection,
        totalSize: Int64,
        received: inout Int64,
        fileHandle: FileHandle,
        progress: @escaping @Sendable (Double) -> Void,
        continuation: CheckedContinuation<Void, Error>
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
            if let error {
                continuation.resume(throwing: ProviderError.networkError(error.localizedDescription))
                return
            }
            if let data {
                try? fileHandle.write(contentsOf: data)
                received += Int64(data.count)
                if totalSize > 0 { progress(Double(received) / Double(totalSize)) }
            }
            if isComplete {
                connection.cancel()
                continuation.resume()
            } else {
                self.receiveChunked(connection: connection, totalSize: totalSize, received: &received, fileHandle: fileHandle, progress: progress, continuation: continuation)
            }
        }
    }

    // MARK: - Parsers

    private func parsePASV(_ response: String) -> (String, Int)? {
        // 227 Entering Passive Mode (h1,h2,h3,h4,p1,p2)
        guard let start = response.firstIndex(of: "("),
              let end = response.firstIndex(of: ")") else { return nil }
        let inner = String(response[response.index(after: start)..<end])
        let parts = inner.split(separator: ",").compactMap { Int($0) }
        guard parts.count == 6 else { return nil }
        let host = "\(parts[0]).\(parts[1]).\(parts[2]).\(parts[3])"
        let port = parts[4] * 256 + parts[5]
        return (host, port)
    }

    private func parseEPSV(_ response: String) -> Int? {
        // 229 Entering Extended Passive Mode (|||port|)
        guard let start = response.firstIndex(of: "("),
              let end = response.firstIndex(of: ")") else { return nil }
        let inner = String(response[response.index(after: start)..<end])
        let parts = inner.split(separator: "|")
        guard parts.count >= 4, let port = Int(parts[3]) else { return nil }
        return port
    }

    private func parseMlsd(_ listing: String, path: String) -> [FileItem] {
        listing.components(separatedBy: "\n").compactMap { line -> FileItem? in
            let line = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { return nil }

            var facts: [String: String] = [:]
            let parts = line.components(separatedBy: " ")
            guard parts.count >= 2 else { return nil }

            let factsStr = parts[0]
            let nameStart = parts.dropFirst().joined(separator: " ")

            for fact in factsStr.split(separator: ";") {
                let kv = fact.split(separator: "=", maxSplits: 1)
                if kv.count == 2 {
                    facts[String(kv[0]).lowercased()] = String(kv[1])
                }
            }

            let name = nameStart
            let isDir = facts["type"]?.lowercased().contains("dir") ?? false
            let size = facts["size"].flatMap { Int64($0) }
            let modDate: Date? = facts["modify"].flatMap { parseMLSDate($0) }
            let fullPath = (path as NSString).appendingPathComponent(name)
            let url = URL(string: "ftp://\(config.host)\(fullPath)") ?? URL(fileURLWithPath: fullPath)

            if isDir {
                return FileItem.makeDirectory(name: name, path: fullPath, url: url, providerID: id, modDate: modDate)
            } else {
                return FileItem.makeFile(name: name, path: fullPath, url: url, size: size, modDate: modDate, providerID: id)
            }
        }
    }

    private func parseMLSDate(_ str: String) -> Date? {
        // YYYYMMDDHHMMSS or YYYYMMDDHHMMSSfrac
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: String(str.prefix(14)))
    }

    private func assertConnected() throws {
        guard _isConnected else { throw ProviderError.notConnected }
    }
}
