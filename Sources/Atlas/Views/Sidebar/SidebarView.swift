import SwiftUI

struct SidebarView: View {
    var sidebarVM: SidebarViewModel
    @Binding var selectedLocation: SidebarLocation?
    @State private var appVM = AppViewModel.shared
    @State private var showingAddConnection = false
    @State private var showingFolderPicker = false

    var body: some View {
        List(selection: $selectedLocation) {
            // Local Storage — app Documents folder
            Section("On This Device") {
                ForEach(sidebarVM.localLocations, id: \.path) { loc in
                    SidebarRowView(
                        name: loc.name,
                        icon: loc.icon,
                        color: .blue,
                        location: SidebarLocation(providerID: "local", path: loc.path, name: loc.name)
                    )
                }
            }

            // User-pinned folders from Files App (UIDocumentPickerViewController)
            if !sidebarVM.pinnedFolders.isEmpty {
                Section("Locations") {
                    ForEach(sidebarVM.pinnedFolders) { folder in
                        SidebarRowView(
                            name: folder.name,
                            icon: "folder.fill",
                            color: .orange,
                            location: SidebarLocation(providerID: "local", path: folder.path, name: folder.name)
                        )
                        .contextMenu {
                            Button(role: .destructive) {
                                sidebarVM.removePinnedFolder(path: folder.path)
                            } label: {
                                Label("Remove Location", systemImage: "minus.circle")
                            }
                        }
                    }
                    .onDelete { offsets in sidebarVM.removePinnedFolder(at: offsets) }
                }
            }

            // Browse button — opens UIDocumentPickerViewController
            Section {
                Button {
                    showingFolderPicker = true
                } label: {
                    Label("Browse Files App…", systemImage: "folder.badge.plus")
                        .foregroundStyle(.blue)
                }
            }

            // Cloud Storage
            let cloudProviders = appVM.providers.filter { $0.connectionType.isCloud }
            if !cloudProviders.isEmpty {
                Section("Cloud") {
                    ForEach(cloudProviders, id: \.id) { provider in
                        SidebarRowView(
                            name: provider.name,
                            icon: provider.icon,
                            color: .blue,
                            location: SidebarLocation(providerID: provider.id, path: provider.rootPath, name: provider.name)
                        )
                    }
                }
            }

            // Network Connections (FTP, WebDAV, SMB)
            let networkProviders = appVM.providers.filter { !$0.connectionType.isCloud && $0.id != "local" && $0.id != "icloud" }
            Section("Network") {
                ForEach(networkProviders, id: \.id) { provider in
                    SidebarRowView(
                        name: provider.name,
                        icon: provider.icon,
                        color: .orange,
                        location: SidebarLocation(providerID: provider.id, path: provider.rootPath, name: provider.name)
                    )
                    .contextMenu {
                        Button(role: .destructive) {
                            appVM.removeProvider(id: provider.id)
                        } label: {
                            Label("Remove Connection", systemImage: "trash")
                        }
                    }
                }
                Button {
                    showingAddConnection = true
                } label: {
                    Label("Add Connection…", systemImage: "plus.circle")
                        .foregroundStyle(.blue)
                }
            }

            // Bookmarks
            if !sidebarVM.bookmarks.isEmpty {
                Section("Bookmarks") {
                    ForEach(sidebarVM.bookmarks) { bookmark in
                        SidebarRowView(
                            name: bookmark.name,
                            icon: bookmark.icon,
                            color: .yellow,
                            location: SidebarLocation(providerID: bookmark.providerID, path: bookmark.path, name: bookmark.name)
                        )
                        .contextMenu {
                            Button(role: .destructive) {
                                sidebarVM.removeBookmark(path: bookmark.path)
                            } label: {
                                Label("Remove Bookmark", systemImage: "bookmark.slash")
                            }
                        }
                    }
                    .onMove { from, to in sidebarVM.reorderBookmarks(from: from, to: to) }
                    .onDelete { offsets in sidebarVM.removeBookmark(at: offsets) }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Atlas Files")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        appVM.showingConnections = true
                    } label: {
                        Label("Manage Connections", systemImage: "network")
                    }
                    Toggle(isOn: $appVM.showHiddenFiles) {
                        Label("Show Hidden Files", systemImage: "eye.slash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingAddConnection) {
            AddConnectionView { config in
                ConnectionStore.shared.add(config)
                if let provider = appVM.makeProvider(for: config) {
                    appVM.addProvider(provider)
                }
            }
        }
        .sheet(isPresented: $showingFolderPicker) {
            DocumentFolderPicker { url in
                sidebarVM.addPinnedFolder(url: url)
                showingFolderPicker = false
                // Navigate into the newly pinned folder
                selectedLocation = SidebarLocation(providerID: "local", path: url.path, name: url.lastPathComponent)
            }
        }
    }
}

struct SidebarRowView: View {
    let name: String
    let icon: String
    let color: Color
    let location: SidebarLocation

    var body: some View {
        Label {
            Text(name)
                .lineLimit(1)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(color)
        }
        .tag(location)
    }
}
