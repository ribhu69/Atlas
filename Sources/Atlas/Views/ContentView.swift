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
            let provider = appVM.provider(for: location.providerID) ?? LocalFileProvider()
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
            // Default: navigate to local on first launch
            let local = SidebarLocation(providerID: "local", path: NSHomeDirectory(), name: "On My iPhone")
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
