import Foundation
import SwiftUI

// MARK: - File Action

struct FileAction: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let systemImage: String
    let role: ButtonRole?
    let isDestructive: Bool
    let handler: @MainActor @Sendable (FileItem) -> Void

    init(title: String, systemImage: String, role: ButtonRole? = nil, isDestructive: Bool = false, handler: @escaping @MainActor @Sendable (FileItem) -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.isDestructive = isDestructive
        self.handler = handler
    }
}

struct FileActionGroup: Identifiable, Sendable {
    let id = UUID()
    let title: String?
    let actions: [FileAction]
}

// MARK: - Action Provider

@MainActor
struct FileActionProvider {

    let item: FileItem
    let provider: any StorageProvider
    let onRefresh: @Sendable () -> Void
    let onOpen: @Sendable (FileItem) -> Void
    let onPreview: @Sendable (FileItem) -> Void
    let onEdit: @Sendable (FileItem) -> Void
    let onShare: @Sendable ([FileItem]) -> Void
    let onCopyTo: @Sendable (FileItem) -> Void
    let onMoveTo: @Sendable (FileItem) -> Void
    let onRename: @Sendable (FileItem) -> Void
    let onDelete: @Sendable ([FileItem]) -> Void
    let onCompress: @Sendable ([FileItem]) -> Void
    let onDecompress: @Sendable (FileItem) -> Void
    let onShowInfo: @Sendable (FileItem) -> Void
    let onDownload: @Sendable (FileItem) -> Void
    let onPlay: @Sendable (FileItem) -> Void

    func actionGroups() -> [FileActionGroup] {
        var groups: [FileActionGroup] = []

        // Primary actions
        groups.append(FileActionGroup(title: nil, actions: primaryActions()))

        // Edit actions
        let editActions = editableActions()
        if !editActions.isEmpty {
            groups.append(FileActionGroup(title: nil, actions: editActions))
        }

        // File operation actions
        groups.append(FileActionGroup(title: nil, actions: operationActions()))

        // Archive actions
        let archiveActions = archiveSpecificActions()
        if !archiveActions.isEmpty {
            groups.append(FileActionGroup(title: nil, actions: archiveActions))
        }

        // Sharing
        groups.append(FileActionGroup(title: nil, actions: sharingActions()))

        // Destructive actions
        groups.append(FileActionGroup(title: nil, actions: destructiveActions()))

        return groups
    }

    // MARK: - Action Groups

    private func primaryActions() -> [FileAction] {
        var actions: [FileAction] = []

        switch item.fileType {
        case .directory:
            actions.append(FileAction(title: "Open", systemImage: "folder.fill") { [onOpen] item in onOpen(item) })

        case .image:
            actions.append(FileAction(title: "View Image", systemImage: "photo") { [onPreview] item in onPreview(item) })
            actions.append(FileAction(title: "Set as Wallpaper", systemImage: "paintbrush") { item in
                // UIImage wallpaper via Photos API
            })

        case .video:
            actions.append(FileAction(title: "Play Video", systemImage: "play.fill") { [onPlay] item in onPlay(item) })
            actions.append(FileAction(title: "Preview", systemImage: "eye") { [onPreview] item in onPreview(item) })

        case .audio:
            actions.append(FileAction(title: "Play Audio", systemImage: "music.note") { [onPlay] item in onPlay(item) })

        case .pdf:
            actions.append(FileAction(title: "Open PDF", systemImage: "doc.richtext") { [onPreview] item in onPreview(item) })

        case .document, .spreadsheet, .presentation:
            actions.append(FileAction(title: "Open", systemImage: "doc.text") { [onPreview] item in onPreview(item) })

        case .text, .code:
            actions.append(FileAction(title: "View", systemImage: "doc.plaintext") { [onPreview] item in onPreview(item) })
            actions.append(FileAction(title: "Edit", systemImage: "pencil") { [onEdit] item in onEdit(item) })

        case .archive:
            actions.append(FileAction(title: "Extract Here", systemImage: "archivebox.fill") { [onDecompress] item in onDecompress(item) })
            actions.append(FileAction(title: "Preview Contents", systemImage: "list.bullet") { [onPreview] item in onPreview(item) })

        default:
            actions.append(FileAction(title: "Open", systemImage: "arrow.up.right.square") { [onOpen] item in onOpen(item) })
        }

        if !item.isDirectory {
            actions.append(FileAction(title: "Quick Look", systemImage: "eye.fill") { [onPreview] item in onPreview(item) })
        }

        return actions
    }

    private func editableActions() -> [FileAction] {
        guard item.fileType.isEditable else { return [] }
        return [
            FileAction(title: "Edit in Text Editor", systemImage: "pencil.and.outline") { [onEdit] item in onEdit(item) }
        ]
    }

    private func operationActions() -> [FileAction] {
        var actions: [FileAction] = []
        if !item.isDirectory {
            actions.append(FileAction(title: "Download", systemImage: "arrow.down.circle") { [onDownload] item in onDownload(item) })
        }
        actions.append(FileAction(title: "Copy to…", systemImage: "doc.on.doc") { [onCopyTo] item in onCopyTo(item) })
        actions.append(FileAction(title: "Move to…", systemImage: "folder.badge.plus") { [onMoveTo] item in onMoveTo(item) })
        actions.append(FileAction(title: "Rename", systemImage: "pencil") { [onRename] item in onRename(item) })
        actions.append(FileAction(title: "Compress", systemImage: "archivebox") { [onCompress] item in onCompress([item]) })
        actions.append(FileAction(title: "Copy Path", systemImage: "link") { item in
            UIPasteboard.general.string = item.path
        })
        actions.append(FileAction(title: "Get Info", systemImage: "info.circle") { [onShowInfo] item in onShowInfo(item) })
        return actions
    }

    private func archiveSpecificActions() -> [FileAction] {
        guard item.fileType == .archive else { return [] }
        return [
            FileAction(title: "Extract to…", systemImage: "archivebox.circle") { [onDecompress] item in onDecompress(item) }
        ]
    }

    private func sharingActions() -> [FileAction] {
        return [
            FileAction(title: "Share", systemImage: "square.and.arrow.up") { [onShare] item in onShare([item]) }
        ]
    }

    private func destructiveActions() -> [FileAction] {
        return [
            FileAction(title: "Delete", systemImage: "trash", role: .destructive, isDestructive: true) { [onDelete] item in onDelete([item]) }
        ]
    }

    // MARK: - Multi-selection actions

    static func multiSelectActions(
        items: [FileItem],
        onShare: @escaping @MainActor @Sendable ([FileItem]) -> Void,
        onCopy: @escaping @MainActor @Sendable ([FileItem]) -> Void,
        onMove: @escaping @MainActor @Sendable ([FileItem]) -> Void,
        onDelete: @escaping @MainActor @Sendable ([FileItem]) -> Void,
        onCompress: @escaping @MainActor @Sendable ([FileItem]) -> Void,
        onDownload: @escaping @MainActor @Sendable ([FileItem]) -> Void
    ) -> [FileActionGroup] {
        let actions = [
            FileAction(title: "Share \(items.count) Items", systemImage: "square.and.arrow.up") { _ in onShare(items) },
            FileAction(title: "Copy to…", systemImage: "doc.on.doc") { _ in onCopy(items) },
            FileAction(title: "Move to…", systemImage: "folder.badge.plus") { _ in onMove(items) },
            FileAction(title: "Download", systemImage: "arrow.down.circle") { _ in onDownload(items) },
            FileAction(title: "Compress \(items.count) Items", systemImage: "archivebox") { _ in onCompress(items) },
            FileAction(title: "Delete \(items.count) Items", systemImage: "trash", role: .destructive, isDestructive: true) { _ in onDelete(items) }
        ]
        return [FileActionGroup(title: "Selected \(items.count) items", actions: actions)]
    }
}
