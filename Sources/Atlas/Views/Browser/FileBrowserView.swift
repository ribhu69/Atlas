import SwiftUI
import QuickLook

struct FileBrowserView: View {
    @State var vm: FileBrowserViewModel
    var sidebarVM: SidebarViewModel
    @Binding var isDualPane: Bool

    @State private var showingPreview: FileItem?
    @State private var showingInfo: FileItem?
    @State private var showingCompress: Bool = false
    @State private var compressName: String = "archive"
    @State private var showingPicker: Bool = false
    @State private var pickerMode: PickerMode = .copyTo
    @State private var appVM = AppViewModel.shared
    @State private var mediaItem: FileItem?
    @State private var showingTextEditor: FileItem?
    @State private var showingShare: Bool = false
    @State private var shareItems: [Any] = []

    enum PickerMode { case copyTo, moveTo }

    var body: some View {
        Group {
            if vm.isLoading && vm.items.isEmpty {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = vm.error {
                ContentUnavailableView {
                    Label("Error Loading", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error.localizedDescription)
                } actions: {
                    Button("Retry") { Task { await vm.load() } }
                        .buttonStyle(.bordered)
                }
            } else if vm.filteredItems.isEmpty {
                ContentUnavailableView("Empty Folder", systemImage: "folder", description: Text("This folder is empty"))
            } else {
                contentView
            }
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .searchable(text: $vm.searchQuery, prompt: "Search files…")
        .refreshable { await vm.refresh() }
        .confirmationDialog("Delete Items?", isPresented: $vm.showingDeleteConfirmation) {
            Button("Delete \(vm.itemsToDelete.count) item(s)", role: .destructive) {
                Task { await vm.delete(items: vm.itemsToDelete) }
            }
        } message: {
            Text("This action cannot be undone.")
        }
        .alert("Rename", isPresented: .init(
            get: { vm.itemToRename != nil },
            set: { if !$0 { vm.itemToRename = nil } }
        )) {
            TextField("Name", text: $vm.renameText)
            Button("Rename") {
                if let item = vm.itemToRename, !vm.renameText.isEmpty {
                    Task { await vm.rename(item: item, to: vm.renameText) }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("New Folder", isPresented: $vm.showingNewFolderDialog) {
            TextField("Folder Name", text: $vm.newFolderName)
            Button("Create") {
                if !vm.newFolderName.isEmpty {
                    Task { await vm.createFolder(named: vm.newFolderName) }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: .init(get: { showingInfo != nil }, set: { if !$0 { showingInfo = nil } })) {
            if let item = showingInfo {
                FileInfoView(item: item)
            }
        }
        .sheet(isPresented: .init(get: { showingTextEditor != nil }, set: { if !$0 { showingTextEditor = nil } })) {
            if let item = showingTextEditor {
                TextEditorView(item: item, provider: vm.provider)
            }
        }
        .sheet(isPresented: .init(get: { mediaItem != nil }, set: { if !$0 { mediaItem = nil } })) {
            if let item = mediaItem {
                MediaPlayerView(item: item)
            }
        }
        .sheet(isPresented: $showingCompress) {
            compressSheet
        }
        .sheet(isPresented: $showingShare) {
            ActivityView(activityItems: shareItems)
        }
        .fullScreenCover(isPresented: .init(get: { showingPreview != nil }, set: { if !$0 { showingPreview = nil } })) {
            if let item = showingPreview {
                QuickLookPreview(item: item)
            }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch vm.viewMode {
        case .list:
            FileListView(vm: vm, onAction: handleAction)
        case .grid:
            FileGridView(vm: vm, onAction: handleAction)
        case .columns:
            FileListView(vm: vm, onAction: handleAction)
        }
    }

    private var navigationTitle: String {
        if vm.isSelecting { return "\(vm.selectionCount) Selected" }
        return URL(fileURLWithPath: vm.currentPath).lastPathComponent.isEmpty ? vm.provider.name : URL(fileURLWithPath: vm.currentPath).lastPathComponent
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if vm.isSelecting {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Done") { vm.deselectAll() }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                selectionToolbar
            }
        } else {
            ToolbarItem(placement: .navigationBarLeading) {
                if vm.canGoBack {
                    Button { Task { await vm.goBack() } } label: {
                        Image(systemName: "chevron.left")
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                    sortMenu
                    viewModeMenu
                    addMenu
                    optionsMenu
                }
            }
        }

        ToolbarItem(placement: .bottomBar) {
            breadcrumbBar
        }
    }

    private var selectionToolbar: some View {
        HStack {
            Button { shareSelected() } label: { Image(systemName: "square.and.arrow.up") }
            Button { vm.download(items: Array(vm.selectedItems)) } label: { Image(systemName: "arrow.down.circle") }
            Button { appVM.setClipboard(items: Array(vm.selectedItems), mode: .copy) } label: { Image(systemName: "doc.on.doc") }
            Button { appVM.setClipboard(items: Array(vm.selectedItems), mode: .cut) } label: { Image(systemName: "scissors") }
            Button {
                vm.itemsToDelete = Array(vm.selectedItems)
                vm.showingDeleteConfirmation = true
            } label: { Image(systemName: "trash").foregroundStyle(.red) }
        }
    }

    private var sortMenu: some View {
        Menu {
            ForEach(SortOption.allCases, id: \.self) { option in
                Button {
                    vm.sortOption = option
                } label: {
                    HStack {
                        Text(option.rawValue)
                        if vm.sortOption == option { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
    }

    private var viewModeMenu: some View {
        Menu {
            ForEach(ViewMode.allCases, id: \.self) { mode in
                Button {
                    vm.viewMode = mode
                } label: {
                    Label(mode.rawValue, systemImage: mode.systemImage)
                }
            }
        } label: {
            Image(systemName: vm.viewMode.systemImage)
        }
    }

    private var addMenu: some View {
        Menu {
            Button {
                vm.newFolderName = ""
                vm.showingNewFolderDialog = true
            } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
            }
            Button {
                showingPicker = true
                pickerMode = .copyTo
            } label: {
                Label("Upload File…", systemImage: "arrow.up.doc")
            }
            if let clip = appVM.clipboard {
                Divider()
                Button {
                    Task { await vm.paste(clipboard: clip) }
                } label: {
                    Label("Paste \(clip.items.count) item(s)", systemImage: "doc.on.clipboard")
                }
            }
        } label: {
            Image(systemName: "plus")
        }
    }

    private var optionsMenu: some View {
        Menu {
            Toggle(isOn: $vm.showHidden) {
                Label("Show Hidden Files", systemImage: "eye.slash")
            }
            Toggle(isOn: $isDualPane) {
                Label("Dual Pane", systemImage: "rectangle.split.2x1")
            }
            Button {
                sidebarVM.addBookmark(item: FileItem.makeDirectory(
                    name: URL(fileURLWithPath: vm.currentPath).lastPathComponent,
                    path: vm.currentPath,
                    url: URL(fileURLWithPath: vm.currentPath),
                    providerID: vm.provider.id
                ))
            } label: {
                Label("Bookmark This Folder", systemImage: "bookmark")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    private var breadcrumbBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(vm.pathComponents, id: \.path) { component in
                    Button(component.name) {
                        Task { await vm.navigate(toPath: component.path) }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    if component.path != vm.currentPath {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal)
        }
        .frame(maxWidth: .infinity)
    }

    private var compressSheet: some View {
        NavigationStack {
            Form {
                Section("Archive Name") {
                    TextField("archive", text: $compressName)
                }
                Section("Items: \(vm.selectedItems.count)"){}
            }
            .navigationTitle("Create Archive")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Compress") {
                        vm.compress(items: Array(vm.selectedItems), name: compressName)
                        showingCompress = false
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingCompress = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Action Handler

    func handleAction(_ action: BrowserAction, _ item: FileItem) {
        switch action {
        case .open:
            if item.isDirectory {
                Task { await vm.navigate(to: item) }
            } else {
                handleOpen(item)
            }
        case .preview:
            showingPreview = item
        case .edit:
            showingTextEditor = item
        case .play:
            mediaItem = item
        case .rename:
            vm.itemToRename = item
            vm.renameText = item.name
        case .delete:
            vm.itemsToDelete = [item]
            vm.showingDeleteConfirmation = true
        case .copyTo:
            appVM.setClipboard(items: [item], mode: .copy)
        case .moveTo:
            appVM.setClipboard(items: [item], mode: .cut)
        case .compress:
            vm.selectedItems = [item]
            compressName = item.name
            showingCompress = true
        case .decompress:
            vm.decompress(item: item)
        case .share:
            shareItems = [item.url]
            showingShare = true
        case .download:
            vm.download(items: [item])
        case .bookmark:
            sidebarVM.addBookmark(item: item)
        case .info:
            showingInfo = item
        }
    }

    private func handleOpen(_ item: FileItem) {
        switch item.fileType {
        case .video, .audio:
            mediaItem = item
        case .text, .code:
            showingTextEditor = item
        default:
            showingPreview = item
        }
    }

    private func shareSelected() {
        shareItems = Array(vm.selectedItems).map { $0.url }
        showingShare = true
    }
}

enum BrowserAction {
    case open, preview, edit, play, rename, delete
    case copyTo, moveTo, compress, decompress
    case share, download, bookmark, info
}
