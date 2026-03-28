import Foundation
import CryptoKit

struct OpenClawDeviceIdentity: Codable {
    let privateKeyRaw: Data

    init(privateKeyRaw: Data) {
        self.privateKeyRaw = privateKeyRaw
    }

    init() {
        self.privateKeyRaw = Curve25519.Signing.PrivateKey().rawRepresentation
    }

    var privateKey: Curve25519.Signing.PrivateKey {
        try! Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyRaw)
    }

    var publicKeyRaw: Data {
        privateKey.publicKey.rawRepresentation
    }

    var publicKeyBase64URL: String {
        publicKeyRaw.base64URLEncodedString()
    }

    var deviceId: String {
        let digest = SHA256.hash(data: publicKeyRaw)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func signatureBase64URL(for payload: String) -> String {
        let data = Data(payload.utf8)
        let signature = try! privateKey.signature(for: data)
        return signature.base64URLEncodedString()
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        self.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

enum OpenClawSigning {
    static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func buildV3Payload(deviceId: String, clientId: String, clientMode: String, role: String, scopes: [String], signedAtMs: Int64, token: String, nonce: String, platform: String, deviceFamily: String) -> String {
        [
            "v3",
            deviceId,
            clientId,
            clientMode,
            role,
            scopes.joined(separator: ","),
            String(signedAtMs),
            token,
            nonce,
            normalized(platform),
            normalized(deviceFamily)
        ].joined(separator: "|")
    }
}
