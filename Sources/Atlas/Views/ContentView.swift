import SwiftUI

struct ContentView: View {
    @State private var appVM = AppViewModel.shared
    @State private var sidebarVM = SidebarViewModel()
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var selectedLocation: SidebarLocation?
    @State private var browserVM: FileBrowserViewModel?
    @State private var secondaryBrowserVM: FileBrowserViewModel?
    @State private var isDualPane: Bool = false
    @State private var showingTransfers: Bool = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                sidebarVM: sidebarVM,
                selectedLocation: $selectedLocation
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } content: {
            if let vm = browserVM {
                FileBrowserView(vm: vm, sidebarVM: sidebarVM, isDualPane: $isDualPane)
            } else {
                ContentUnavailableView("Select a Location", systemImage: "folder", description: Text("Choose a folder from the sidebar"))
            }
        } detail: {
            if isDualPane, let vm = secondaryBrowserVM {
                FileBrowserView(vm: vm, sidebarVM: sidebarVM, isDualPane: $isDualPane)
                    .navigationTitle("Secondary")
            } else {
                EmptyView()
            }
        }
        .onChange(of: selectedLocation) { _, location in
            guard let location else { return }
            let provider: any StorageProvider
            if location.providerID == "local" {
                // Check if this path is a user-pinned security-scoped folder
                let pinned = sidebarVM.pinnedFolders.first(where: { $0.path == location.path })
                if let pinned {
                    let resolvedURL = sidebarVM.resolveURL(for: pinned)
                    let rootPath = resolvedURL?.path ?? location.path
                    provider = LocalFileProvider(rootPath: rootPath, securityScoped: true)
                } else {
                    provider = LocalFileProvider(rootPath: location.path)
                }
            } else {
                provider = appVM.provider(for: location.providerID) ?? LocalFileProvider()
            }
            browserVM = FileBrowserViewModel(provider: provider, path: location.path)
            Task { await browserVM?.load() }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                transfersButton
            }
        }
        .sheet(isPresented: $showingTransfers) {
            TransferProgressView()
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $appVM.showingConnections) {
            ConnectionManagerView()
        }
        .alert("Error", isPresented: $appVM.showingError, presenting: appVM.currentError) { _ in
            Button("OK") {}
        } message: { error in
            Text(error.message)
        }
        .onAppear {
            let local = SidebarLocation(
                providerID: "local",
                path: LocalFileProvider.documentsURL.path,
                name: "On My iPhone"
            )
            selectedLocation = local
        }
    }

    private var transfersButton: some View {
        Button {
            showingTransfers = true
        } label: {
            let transfers = TransfersViewModel.shared
            if transfers.hasActive {
                Label("\(transfers.activeOperations.count) Transfers", systemImage: "arrow.up.arrow.down.circle.fill")
                    .foregroundStyle(.blue)
            } else {
                Image(systemName: "arrow.up.arrow.down.circle")
            }
        }
    }
}

struct SidebarLocation: Hashable {
    let providerID: String
    let path: String
    let name: String
}
