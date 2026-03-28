import Foundation

struct SetupCodePayload: Codable {
    let url: String
    let bootstrapToken: String
}

struct GatewayEventFrame<T: Decodable>: Decodable {
    let type: String
    let event: String
    let payload: T
}

struct ConnectChallengePayload: Codable {
    let nonce: String
    let ts: Int64
}

struct GatewayErrorDetails: Codable {
    let code: String?
    let requestId: String?
    let reason: String?
    let authReason: String?
    let recommendedNextStep: String?
}

struct GatewayErrorShape: Codable {
    let code: String
    let message: String
    let details: GatewayErrorDetails?
}

struct GatewayResponseFrame<T: Decodable>: Decodable {
    let type: String
    let id: String
    let ok: Bool
    let payload: T?
    let error: GatewayErrorShape?
}

struct GatewayConnectPayload: Codable {
    let auth: GatewayConnectAuthPayload?
}

struct GatewayConnectAuthPayload: Codable {
    let deviceToken: String?
    let role: String?
    let scopes: [String]?
    let issuedAtMs: Int64?
}

struct ConnectRequestFrame: Encodable {
    let type = "req"
    let id: String
    let method = "connect"
    let params: ConnectParams
}

struct ConnectParams: Encodable {
    let minProtocol: Int
    let maxProtocol: Int
    let locale: String
    let userAgent: String
    let client: ConnectClient
    let role: String
    let scopes: [String]
    let caps: [String]
    let device: DeviceIdentityPayload?
    let auth: ConnectAuth
}

struct ConnectClient: Encodable {
    let id: String
    let version: String
    let mode: String
    let platform: String
    let deviceFamily: String
}

struct ConnectAuth: Encodable {
    let token: String?
    let bootstrapToken: String?
    let deviceToken: String?
    let password: String?
}

struct DeviceIdentityPayload: Encodable {
    let id: String
    let publicKey: String
    let signature: String
    let signedAt: Int64
    let nonce: String
}

struct HelloOKFrame: Decodable {
    let type: String
    let protocolVersion: Int?

    enum CodingKeys: String, CodingKey {
        case type
        case protocolVersion = "protocol"
    }
}

enum GatewayAuthState: Equatable {
    case idle
    case connecting
    case waitingForChallenge
    case waitingForApproval(requestId: String?)
    case connected
    case failed(message: String)
}
