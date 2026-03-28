import Foundation

final class OpenClawSessionStore {
    private let service = "HomeAI.OpenClaw"
    private let identityAccount = "deviceIdentity"
    private let tokenAccount = "deviceToken"

    func loadIdentity() -> OpenClawDeviceIdentity? {
        guard let data = KeychainHelper.load(service: service, account: identityAccount) else { return nil }
        return try? JSONDecoder().decode(OpenClawDeviceIdentity.self, from: data)
    }

    func saveIdentity(_ identity: OpenClawDeviceIdentity) {
        guard let data = try? JSONEncoder().encode(identity) else { return }
        KeychainHelper.save(data, service: service, account: identityAccount)
    }

    func loadDeviceToken() -> String? {
        guard let data = KeychainHelper.load(service: service, account: tokenAccount) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func saveDeviceToken(_ token: String) {
        KeychainHelper.save(Data(token.utf8), service: service, account: tokenAccount)
    }
}
