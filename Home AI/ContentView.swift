import SwiftUI
import SwiftData

struct ContentView: View {
    @StateObject private var gateway = OpenClawGatewayClient()
    @StateObject private var settings = AppSettings()

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    TextField("Gateway URL override", text: $settings.gatewayURLOverride)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Gateway token (optional)", text: $settings.gatewayToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Setup code", text: $settings.setupCode, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Status") {
                    Text(statusText)
                        .foregroundStyle(statusColor)
                }

                Section("Actions") {
                    Button("Connect") { gateway.connect(using: settings) }
                    Button("Disconnect", role: .destructive) { gateway.disconnect() }
                    Button("Clear Logs") { gateway.clearLogs() }
                }

                Section("Logs") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(gateway.logLines.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.system(.footnote, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .frame(minHeight: 240)
                }
            }
            .navigationTitle("Home AI")
        }
    }

    private var statusText: String {
        switch gateway.state {
        case .idle:
            return "Idle"
        case .connecting:
            return "Connecting"
        case .waitingForChallenge:
            return "Waiting for challenge"
        case .waitingForApproval(let requestId):
            return "Waiting for approval\(requestId.map { " (\($0))" } ?? "")"
        case .connected:
            return "Connected"
        case .failed(let message):
            return "Failed: \(message)"
        }
    }

    private var statusColor: Color {
        switch gateway.state {
        case .connected:
            return .green
        case .waitingForApproval:
            return .orange
        case .failed:
            return .red
        default:
            return .primary
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
