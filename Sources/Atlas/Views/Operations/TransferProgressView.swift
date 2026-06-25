import SwiftUI

struct TransferProgressView: View {
    @State private var transfersVM = TransfersViewModel.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if !transfersVM.activeOperations.isEmpty {
                    Section("Active") {
                        ForEach(transfersVM.activeOperations) { op in
                            OperationRowView(op: op)
                        }
                    }
                }
                if !transfersVM.completedOperations.isEmpty {
                    Section("Completed") {
                        ForEach(transfersVM.completedOperations) { op in
                            OperationRowView(op: op)
                        }
                    }
                }
                if transfersVM.activeOperations.isEmpty && transfersVM.completedOperations.isEmpty {
                    ContentUnavailableView("No Transfers", systemImage: "arrow.up.arrow.down", description: Text("File transfers will appear here"))
                }
            }
            .navigationTitle("Transfers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !transfersVM.activeOperations.isEmpty {
                        Button("Cancel All") {
                            FileOperationEngine.shared.cancelAll()
                        }
                        .foregroundStyle(.red)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        if !transfersVM.completedOperations.isEmpty {
                            Button("Clear") {
                                FileOperationEngine.shared.clearCompleted()
                            }
                        }
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
    }
}

struct OperationRowView: View {
    let op: FileOperation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(op.description)
                        .font(.subheadline)
                        .lineLimit(1)

                    if let errMsg = op.errorMessage {
                        Text(errMsg)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }
                }

                Spacer()

                if op.isActive {
                    Button {
                        op.cancel()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if op.isActive {
                ProgressView(value: op.progress)
                    .tint(statusColor)
                    .animation(.linear, value: op.progress)

                HStack {
                    Text("\(Int(op.progress * 100))%")
                    Spacer()
                    if let started = op.startedAt {
                        Text(RelativeDateTimeFormatter().localizedString(for: started, relativeTo: Date()))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusIcon: String {
        switch op.status {
        case .pending:    return "clock"
        case .running:    return "arrow.up.arrow.down.circle.fill"
        case .completed:  return "checkmark.circle.fill"
        case .failed:     return "xmark.circle.fill"
        case .cancelled:  return "minus.circle.fill"
        }
    }

    private var statusColor: Color {
        switch op.status {
        case .pending:    return .secondary
        case .running:    return .blue
        case .completed:  return .green
        case .failed:     return .red
        case .cancelled:  return .orange
        }
    }
}
