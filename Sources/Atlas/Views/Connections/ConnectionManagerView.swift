import SwiftUI

struct ConnectionManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = ConnectionStore.shared
    @State private var showingAdd = false
    @State private var editingConfig: ConnectionConfig?

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.connections) { config in
                    ConnectionRowView(config: config)
                        .contentShape(Rectangle())
                        .onTapGesture { editingConfig = config }
                        .swipeActions {
                            Button(role: .destructive) {
                                store.delete(config)
                                AppViewModel.shared.removeProvider(id: config.providerID())
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
                .onDelete { offsets in
                    for i in offsets {
                        let config = store.connections[i]
                        store.delete(config)
                        AppViewModel.shared.removeProvider(id: config.providerID())
                    }
                }
            }
            .overlay {
                if store.connections.isEmpty {
                    ContentUnavailableView {
                        Label("No Connections", systemImage: "network")
                    } description: {
                        Text("Add FTP, WebDAV, or cloud storage connections")
                    } actions: {
                        Button("Add Connection") { showingAdd = true }
                            .buttonStyle(.bordered)
                    }
                }
            }
            .navigationTitle("Connections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddConnectionView { config in
                    store.add(config)
                    if let provider = AppViewModel.shared.makeProvider(for: config) {
                        AppViewModel.shared.addProvider(provider)
                    }
                }
            }
            .sheet(item: $editingConfig) { config in
                AddConnectionView(existingConfig: config) { updated in
                    store.update(updated)
                }
            }
        }
    }
}

struct ConnectionRowView: View {
    let config: ConnectionConfig

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: config.type.systemImage)
                .font(.title2)
                .foregroundStyle(config.type.isCloud ? .blue : .orange)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(config.name)
                    .font(.body)
                Text("\(config.type.rawValue) — \(config.displayHost)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let lastConnected = config.lastConnected {
                Text(RelativeDateTimeFormatter().localizedString(for: lastConnected, relativeTo: Date()))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
