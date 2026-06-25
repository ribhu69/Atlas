import Foundation
import UniformTypeIdentifiers

struct FileItem: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let path: String
    let url: URL
    let size: Int64?
    let modificationDate: Date?
    let creationDate: Date?
    let isDirectory: Bool
    let isSymlink: Bool
    let isHidden: Bool
    let permissions: FilePermissions?
    let fileType: FileType
    let providerID: String

    var displayName: String { name }
    var fileExtension: String { (name as NSString).pathExtension.lowercased() }

    static func == (lhs: FileItem, rhs: FileItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct FilePermissions: Sendable, Hashable {
    let owner: PermissionTriad
    let group: PermissionTriad
    let other: PermissionTriad
    let isExecutable: Bool

    struct PermissionTriad: Sendable, Hashable {
        let read: Bool
        let write: Bool
        let execute: Bool

        var octalString: String {
            let r = read ? 4 : 0
            let w = write ? 2 : 0
            let x = execute ? 1 : 0
            return "\(r + w + x)"
        }

        var rwxString: String {
            "\(read ? "r" : "-")\(write ? "w" : "-")\(execute ? "x" : "-")"
        }
    }

    var octalString: String {
        "\(owner.octalString)\(group.octalString)\(other.octalString)"
    }

    var symbolicString: String {
        "\(owner.rwxString)\(group.rwxString)\(other.rwxString)"
    }

    static func from(posixPermissions: Int) -> FilePermissions {
        FilePermissions(
            owner: PermissionTriad(
                read: posixPermissions & 0o400 != 0,
                write: posixPermissions & 0o200 != 0,
                execute: posixPermissions & 0o100 != 0
            ),
            group: PermissionTriad(
                read: posixPermissions & 0o040 != 0,
                write: posixPermissions & 0o020 != 0,
                execute: posixPermissions & 0o010 != 0
            ),
            other: PermissionTriad(
                read: posixPermissions & 0o004 != 0,
                write: posixPermissions & 0o002 != 0,
                execute: posixPermissions & 0o001 != 0
            ),
            isExecutable: posixPermissions & 0o111 != 0
        )
    }
}

extension FileItem {
    static func makeDirectory(name: String, path: String, url: URL, providerID: String, modDate: Date? = nil) -> FileItem {
        FileItem(
            id: "\(providerID):\(path)",
            name: name,
            path: path,
            url: url,
            size: nil,
            modificationDate: modDate,
            creationDate: nil,
            isDirectory: true,
            isSymlink: false,
            isHidden: name.hasPrefix("."),
            permissions: nil,
            fileType: .directory,
            providerID: providerID
        )
    }

    static func makeFile(name: String, path: String, url: URL, size: Int64?, modDate: Date?, providerID: String, permissions: FilePermissions? = nil) -> FileItem {
        let ext = (name as NSString).pathExtension.lowercased()
        let type = FileType.detect(from: name, extension: ext)
        return FileItem(
            id: "\(providerID):\(path)",
            name: name,
            path: path,
            url: url,
            size: size,
            modificationDate: modDate,
            creationDate: nil,
            isDirectory: false,
            isSymlink: false,
            isHidden: name.hasPrefix("."),
            permissions: permissions,
            fileType: type,
            providerID: providerID
        )
    }
}

extension FileItem {
    var formattedSize: String {
        guard let size else { return "--" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var formattedDate: String {
        guard let date = modificationDate else { return "--" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    var formattedAbsoluteDate: String {
        guard let date = modificationDate else { return "--" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
