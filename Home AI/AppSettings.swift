import Foundation

@MainActor
final class AppSettings: ObservableObject {
    @Published var gatewayURLOverride: String {
        didSet { UserDefaults.standard.set(gatewayURLOverride, forKey: Keys.gatewayURLOverride) }
    }

    @Published var setupCode: String {
        didSet { UserDefaults.standard.set(setupCode, forKey: Keys.setupCode) }
    }

    @Published var gatewayToken: String {
        didSet {
            if gatewayToken.isEmpty {
                KeychainHelper.delete(service: Keys.service, account: Keys.gatewayToken)
            } else {
                KeychainHelper.save(Data(gatewayToken.utf8), service: Keys.service, account: Keys.gatewayToken)
            }
        }
    }

    init() {
        self.gatewayURLOverride = UserDefaults.standard.string(forKey: Keys.gatewayURLOverride) ?? "ws://10.0.0.19:18789"
        self.setupCode = UserDefaults.standard.string(forKey: Keys.setupCode) ?? ""
        if let data = KeychainHelper.load(service: Keys.service, account: Keys.gatewayToken),
           let token = String(data: data, encoding: .utf8) {
            self.gatewayToken = token
        } else {
            self.gatewayToken = ""
        }
    }

    private enum Keys {
        static let service = "HomeAI.OpenClaw"
        static let gatewayURLOverride = "homeai.gatewayURLOverride"
        static let setupCode = "homeai.setupCode"
        static let gatewayToken = "gatewayToken"
    }
}
