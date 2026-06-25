import SwiftUI

struct FileListView: View {
    @State var vm: FileBrowserViewModel
    let onAction: (BrowserAction, FileItem) -> Void

    var body: some View {
        List(vm.filteredItems, selection: vm.isSelecting ? $vm.selectedItems : .constant(nil)) { item in
            FileRowView(item: item, isSelected: vm.selectedItems.contains(item), isSelecting: vm.isSelecting)
                .contentShape(Rectangle())
                .onTapGesture {
                    if vm.isSelecting {
                        vm.toggleSelection(of: item)
                    } else {
                        onAction(.open, item)
                    }
                }
                .onLongPressGesture {
                    vm.isSelecting = true
                    vm.selectedItems.insert(item)
                }
                .contextMenu {
                    contextMenu(for: item)
                } preview: {
                    FileContextPreview(item: item)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        onAction(.delete, item)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button {
                        onAction(.rename, item)
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    .tint(.orange)
                }
                .swipeActions(edge: .leading) {
                    Button {
                        onAction(.share, item)
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .tint(.blue)
                    Button {
                        onAction(.bookmark, item)
                    } label: {
                        Label("Bookmark", systemImage: "bookmark")
                    }
                    .tint(.yellow)
                }
        }
        .listStyle(.plain)
        .animation(.default, value: vm.filteredItems.map { $0.id })
    }

    @ViewBuilder
    private func contextMenu(for item: FileItem) -> some View {
        // Open / Play
        if item.isDirectory {
            Button { onAction(.open, item) } label: { Label("Open", systemImage: "folder") }
        } else {
            if item.fileType.isPlayable {
                Button { onAction(.play, item) } label: { Label("Play", systemImage: "play.fill") }
            }
            Button { onAction(.preview, item) } label: { Label("Quick Look", systemImage: "eye") }
            if item.fileType.isEditable {
                Button { onAction(.edit, item) } label: { Label("Edit", systemImage: "pencil") }
            }
        }

        Divider()

        // File ops
        Button { onAction(.rename, item) } label: { Label("Rename", systemImage: "pencil.and.outline") }
        Button { onAction(.copyTo, item) } label: { Label("Copy", systemImage: "doc.on.doc") }
        Button { onAction(.moveTo, item) } label: { Label("Move", systemImage: "folder.badge.plus") }
        Button { onAction(.download, item) } label: { Label("Download", systemImage: "arrow.down.circle") }
        Button { onAction(.compress, item) } label: { Label("Compress", systemImage: "archivebox") }
        if item.fileType == .archive {
            Button { onAction(.decompress, item) } label: { Label("Extract", systemImage: "archivebox.fill") }
        }
        Button { onAction(.bookmark, item) } label: { Label("Bookmark", systemImage: "bookmark") }

        Divider()

        Button { onAction(.share, item) } label: { Label("Share", systemImage: "square.and.arrow.up") }
        Button { onAction(.info, item) } label: { Label("Get Info", systemImage: "info.circle") }

        Divider()

        Button(role: .destructive) { onAction(.delete, item) } label: { Label("Delete", systemImage: "trash") }
    }
}

struct FileRowView: View {
    let item: FileItem
    let isSelected: Bool
    let isSelecting: Bool

    var body: some View {
        HStack(spacing: 12) {
            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .font(.title3)
            }

            FileIconView(item: item, size: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.body)
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                HStack(spacing: 8) {
                    if !item.isDirectory {
                        Text(item.formattedSize)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(item.fileType.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let date = item.formattedDate as String? {
                        Text("·").foregroundStyle(.tertiary).font(.caption)
                        Text(date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if item.isHidden {
                        Image(systemName: "eye.slash.fill")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            if item.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .background(isSelected ? Color.blue.opacity(0.1) : .clear)
        .cornerRadius(8)
    }
}

struct FileContextPreview: View {
    let item: FileItem

    var body: some View {
        VStack(spacing: 8) {
            FileIconView(item: item, size: 80)
            Text(item.name)
                .font(.headline)
            if let size = item.formattedSize as String? {
                Text(size)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 200, height: 160)
    }
}
