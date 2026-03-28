import Foundation

@MainActor
final class OpenClawGatewayClient: ObservableObject {
    @Published var state: GatewayAuthState = .idle
    @Published var logLines: [String] = []

    private let sessionStore = OpenClawSessionStore()
    private var identity: OpenClawDeviceIdentity
    private var socketTask: URLSessionWebSocketTask?
    private var bootstrapTokenInUse: String?
    private var reconnectTask: Task<Void, Never>?

    init() {
        if let stored = sessionStore.loadIdentity() {
            identity = stored
        } else {
            let fresh = OpenClawDeviceIdentity()
            identity = fresh
            sessionStore.saveIdentity(fresh)
        }
    }

    func connect(using settings: AppSettings) {
        Task { await connectInternal(using: settings) }
    }

    func clearLogs() {
        logLines.removeAll()
    }

    func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        socketTask?.cancel(with: .normalClosure, reason: nil)
        socketTask = nil
        state = .idle
        log("Disconnected")
    }

    private func connectInternal(using settings: AppSettings) async {
        reconnectTask?.cancel()
        reconnectTask = nil
        socketTask?.cancel(with: .normalClosure, reason: nil)
        socketTask = nil
        state = .connecting

        let decoded = decodeSetupCode(settings.setupCode)
        bootstrapTokenInUse = decoded?.bootstrapToken
        let override = settings.gatewayURLOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetURLString = override.isEmpty ? (decoded?.url ?? "") : override

        guard let url = URL(string: targetURLString) else {
            state = .failed(message: "Invalid gateway URL")
            log("Invalid gateway URL: \(targetURLString)")
            return
        }

        log("Decoded setup token: \(decoded?.bootstrapToken ?? "<none>")")
        log("Using gateway URL: \(url.absoluteString)")
        log("Device ID: \(identity.deviceId)")

        let request = URLRequest(url: url)
        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: request)
        socketTask = task
        task.resume()
        state = .waitingForChallenge
        log("WS opened")

        receiveLoop(settings: settings)
    }

    private func receiveLoop(settings: AppSettings) {
        socketTask?.receive { [weak self] result in
            guard let self else { return }
            Task { @MainActor in
                switch result {
                case .failure(let error):
                    self.log("Receive error: \(error.localizedDescription)")
                    if case .waitingForApproval = self.state {
                        return
                    }
                    self.state = .failed(message: error.localizedDescription)
                case .success(let message):
                    self.handle(message: message, settings: settings)
                    self.receiveLoop(settings: settings)
                }
            }
        }
    }

    private func handle(message: URLSessionWebSocketTask.Message, settings: AppSettings) {
        switch message {
        case .string(let text):
            log("INBOUND: \(text)")
            handleTextFrame(text, settings: settings)
        case .data(let data):
            let text = String(data: data, encoding: .utf8) ?? "<binary>"
            log("INBOUND(DATA): \(text)")
            handleTextFrame(text, settings: settings)
        @unknown default:
            log("INBOUND: unknown frame")
        }
    }

    private func handleTextFrame(_ text: String, settings: AppSettings) {
        guard let data = text.data(using: .utf8) else { return }

        if let challenge = try? JSONDecoder().decode(GatewayEventFrame<ConnectChallengePayload>.self, from: data),
           challenge.type == "event", challenge.event == "connect.challenge" {
            sendConnect(nonce: challenge.payload.nonce, settings: settings)
            return
        }

        if let hello = try? JSONDecoder().decode(HelloOKFrame.self, from: data), hello.type == "hello-ok" {
            log("Connected successfully")
            state = .connected
            return
        }

        if let response = try? JSONDecoder().decode(GatewayResponseFrame<GatewayConnectPayload>.self, from: data) {
            handleResponse(response, settings: settings)
            return
        }
    }

    private func handleResponse(_ response: GatewayResponseFrame<GatewayConnectPayload>, settings: AppSettings) {
        if response.ok {
            if let deviceToken = response.payload?.auth?.deviceToken {
                sessionStore.saveDeviceToken(deviceToken)
                log("Stored device token")
            }
            log("Response OK for id=\(response.id)")
            state = .connected
            return
        }

        let message = response.error?.message ?? "Unknown gateway error"
        let detailCode = response.error?.details?.code ?? ""
        log("Gateway error: \(message) [\(detailCode)]")

        if detailCode == "PAIRING_REQUIRED" {
            let requestId = response.error?.details?.requestId
            state = .waitingForApproval(requestId: requestId)
            log("Waiting for approval. requestId=\(requestId ?? "<none>")")
            startApprovalReconnectLoop(settings: settings)
            return
        }

        state = .failed(message: message)
    }

    private func startApprovalReconnectLoop(settings: AppSettings) {
        reconnectTask?.cancel()
        reconnectTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                guard case .waitingForApproval = self.state else { return }
                self.log("Retrying connection while waiting for approval...")
                await self.connectInternal(using: settings)
            }
        }
    }

    private func sendConnect(nonce: String, settings: AppSettings) {
        let requestId = UUID().uuidString.uppercased()

        let role = "operator"
        let scopes = [
            "operator.admin",
            "operator.read",
            "operator.write",
            "operator.approvals",
            "operator.pairing"
        ]
        let signedAt = Int64(Date().timeIntervalSince1970 * 1000)
        let client = ConnectClient(
            id: "openclaw-ios",
            version: "home-ai",
            mode: "ui",
            platform: "iOS",
            deviceFamily: "iPhone"
        )

        let deviceToken = sessionStore.loadDeviceToken()
        let bootstrapToken = bootstrapTokenInUse
        let sharedToken = settings.gatewayToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let chosenTokenForSignature = deviceToken ?? bootstrapToken ?? (sharedToken.isEmpty ? nil : sharedToken) ?? ""

        let payload = OpenClawSigning.buildV3Payload(
            deviceId: identity.deviceId,
            clientId: client.id,
            clientMode: client.mode,
            role: role,
            scopes: scopes,
            signedAtMs: signedAt,
            token: chosenTokenForSignature,
            nonce: nonce,
            platform: client.platform,
            deviceFamily: client.deviceFamily
        )

        let device = DeviceIdentityPayload(
            id: identity.deviceId,
            publicKey: identity.publicKeyBase64URL,
            signature: identity.signatureBase64URL(for: payload),
            signedAt: signedAt,
            nonce: nonce
        )

        let auth = ConnectAuth(
            token: sharedToken.isEmpty ? nil : sharedToken,
            bootstrapToken: bootstrapToken,
            deviceToken: deviceToken,
            password: nil
        )

        let frame = ConnectRequestFrame(
            id: requestId,
            params: ConnectParams(
                minProtocol: 3,
                maxProtocol: 3,
                locale: Locale.current.identifier,
                userAgent: "HomeAI/1.0",
                client: client,
                role: role,
                scopes: scopes,
                caps: ["tool-events"],
                device: device,
                auth: auth
            )
        )

        do {
            let data = try JSONEncoder().encode(frame)
            let json = String(decoding: data, as: UTF8.self)
            log("OUTBOUND: \(json)")
            socketTask?.send(.string(json)) { [weak self] error in
                Task { @MainActor in
                    if let error {
                        self?.log("Send error: \(error.localizedDescription)")
                        self?.state = .failed(message: error.localizedDescription)
                    }
                }
            }
        } catch {
            log("Encode error: \(error.localizedDescription)")
            state = .failed(message: error.localizedDescription)
        }
    }

    private func decodeSetupCode(_ code: String) -> SetupCodePayload? {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var b64 = trimmed.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64.append("=") }
        guard let data = Data(base64Encoded: b64) else { return nil }
        return try? JSONDecoder().decode(SetupCodePayload.self, from: data)
    }

    private func log(_ line: String) {
        logLines.append(line)
    }
}
