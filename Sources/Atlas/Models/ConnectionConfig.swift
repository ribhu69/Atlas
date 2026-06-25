import Foundation

enum ConnectionType: String, Codable, CaseIterable, Sendable {
    case ftp = "FTP"
    case ftps = "FTPS"
    case sftp = "SFTP"
    case webdav = "WebDAV"
    case webdavs = "WebDAVS"
    case smb = "SMB"
    case googleDrive = "Google Drive"
    case dropbox = "Dropbox"
    case oneDrive = "OneDrive"
    case iCloud = "iCloud Drive"

    var defaultPort: Int {
        switch self {
        case .ftp:       return 21
        case .ftps:      return 990
        case .sftp:      return 22
        case .webdav:    return 80
        case .webdavs:   return 443
        case .smb:       return 445
        default:         return 0
        }
    }

    var systemImage: String {
        switch self {
        case .ftp, .ftps:        return "server.rack"
        case .sftp:              return "lock.shield"
        case .webdav, .webdavs:  return "network"
        case .smb:               return "desktopcomputer.and.arrow.down"
        case .googleDrive:       return "arrow.triangle.2.circlepath.circle"
        case .dropbox:           return "tray.and.arrow.down.fill"
        case .oneDrive:          return "cloud.fill"
        case .iCloud:            return "icloud.fill"
        }
    }

    var requiresAuth: Bool {
        switch self {
        case .iCloud:
            return false
        default:
            return true
        }
    }

    var isCloud: Bool {
        switch self {
        case .googleDrive, .dropbox, .oneDrive, .iCloud:
            return true
        default:
            return false
        }
    }
}

struct ConnectionConfig: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var type: ConnectionType
    var host: String
    var port: Int
    var username: String
    var password: String
    var remotePath: String
    var isPassiveMode: Bool
    var encoding: String
    var createdAt: Date
    var lastConnected: Date?

    init(
        id: UUID = UUID(),
        name: String,
        type: ConnectionType,
        host: String = "",
        port: Int? = nil,
        username: String = "",
        password: String = "",
        remotePath: String = "/",
        isPassiveMode: Bool = true,
        encoding: String = "UTF-8"
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.host = host
        self.port = port ?? type.defaultPort
        self.username = username
        self.password = password
        self.remotePath = remotePath
        self.isPassiveMode = isPassiveMode
        self.encoding = encoding
        self.createdAt = Date()
    }

    var displayHost: String {
        port != type.defaultPort ? "\(host):\(port)" : host
    }
}

extension ConnectionConfig {
    func providerID() -> String {
        "\(type.rawValue)-\(id.uuidString)"
    }
}

@MainActor
final class ConnectionStore: ObservableObject {
    static let shared = ConnectionStore()

    @Published private(set) var connections: [ConnectionConfig] = []

    private let storeURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("connections.json")
    }()

    init() {
        load()
    }

    func add(_ config: ConnectionConfig) {
        connections.append(config)
        save()
    }

    func update(_ config: ConnectionConfig) {
        if let idx = connections.firstIndex(where: { $0.id == config.id }) {
            connections[idx] = config
            save()
        }
    }

    func delete(_ config: ConnectionConfig) {
        connections.removeAll { $0.id == config.id }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(connections) else { return }
        try? data.write(to: storeURL)
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let configs = try? JSONDecoder().decode([ConnectionConfig].self, from: data) else { return }
        connections = configs
    }
}
