import SwiftUI

struct AddConnectionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var config: ConnectionConfig
    @State private var isTesting: Bool = false
    @State private var testResult: TestResult?
    var onSave: (ConnectionConfig) -> Void

    enum TestResult: Identifiable {
        case success
        case failure(String)
        var id: String { switch self { case .success: return "ok"; case .failure(let m): return m } }
    }

    init(existingConfig: ConnectionConfig? = nil, onSave: @escaping (ConnectionConfig) -> Void) {
        _config = State(initialValue: existingConfig ?? ConnectionConfig(name: "", type: .ftp))
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                // Connection type picker
                Section("Connection Type") {
                    Picker("Type", selection: $config.type) {
                        ForEach(ConnectionType.allCases.filter { !$0.isCloud }, id: \.self) { type in
                            Label(type.rawValue, systemImage: type.systemImage).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: config.type) { _, newType in
                        if config.port == config.type.defaultPort || config.port == 0 {
                            config = ConnectionConfig(
                                id: config.id,
                                name: config.name,
                                type: newType,
                                host: config.host,
                                username: config.username,
                                password: config.password,
                                remotePath: config.remotePath
                            )
                        }
                    }
                }

                // Basic Info
                Section("Server Details") {
                    TextField("Name", text: $config.name, prompt: Text("My Server"))
                    TextField("Host", text: $config.host, prompt: Text("ftp.example.com"))
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    HStack {
                        Text("Port")
                        Spacer()
                        TextField("Port", value: $config.port, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    TextField("Remote Path", text: $config.remotePath, prompt: Text("/"))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                // Authentication
                if config.type.requiresAuth {
                    Section("Authentication") {
                        TextField("Username", text: $config.username)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        SecureField("Password", text: $config.password)
                    }
                }

                // FTP-specific options
                if config.type == .ftp || config.type == .ftps {
                    Section("FTP Options") {
                        Toggle("Passive Mode", isOn: $config.isPassiveMode)
                        Picker("Encoding", selection: $config.encoding) {
                            Text("UTF-8").tag("UTF-8")
                            Text("ISO-8859-1").tag("ISO-8859-1")
                            Text("Windows-1252").tag("Windows-1252")
                        }
                    }
                }

                // Test connection
                Section {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        HStack {
                            if isTesting {
                                ProgressView()
                                    .frame(width: 20, height: 20)
                            } else {
                                Image(systemName: "network.badge.shield.half.filled")
                            }
                            Text("Test Connection")
                        }
                    }
                    .disabled(config.host.isEmpty || isTesting)

                    if let result = testResult {
                        switch result {
                        case .success:
                            Label("Connection successful", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        case .failure(let msg):
                            Label(msg, systemImage: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle(config.name.isEmpty ? "New Connection" : config.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        onSave(config)
                        dismiss()
                    }
                    .disabled(config.name.isEmpty || config.host.isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func testConnection() async {
        guard let provider = AppViewModel.shared.makeProvider(for: config) else {
            testResult = .failure("Unsupported connection type")
            return
        }
        isTesting = true
        defer { isTesting = false }
        do {
            try await provider.connect()
            _ = try await provider.listDirectory(at: config.remotePath)
            await provider.disconnect()
            testResult = .success
        } catch {
            testResult = .failure(error.localizedDescription)
        }
    }
}
