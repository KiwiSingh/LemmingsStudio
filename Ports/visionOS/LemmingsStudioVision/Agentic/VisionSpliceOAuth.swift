import CryptoKit
import Foundation
import Security
import UIKit

struct VisionSpliceOAuthSession: Codable, Sendable {
    var clientID: String
    var tokenEndpoint: URL
    var redirectURI: String
    var codeVerifier: String
    var state: String
}

struct VisionOAuthProtectedResourceMetadata: Decodable {
    var authorization_servers: [String]?
}

struct VisionOAuthAuthorizationMetadata: Decodable {
    var authorization_endpoint: String
    var token_endpoint: String
    var registration_endpoint: String?
}

struct VisionOAuthRegistrationResponse: Decodable {
    var client_id: String
}

struct VisionOAuthTokenResponse: Decodable {
    var access_token: String
    var refresh_token: String?
    var expires_in: Int?
    var token_type: String?
}

enum VisionSpliceOAuthError: LocalizedError {
    case metadata(String)
    case missingCode
    case stateMismatch
    case registrationUnsupported
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .metadata(let value): return "Splice OAuth metadata error: \(value)"
        case .missingCode: return "Splice login callback did not contain an authorization code."
        case .stateMismatch: return "Splice login callback state did not match the pending login session."
        case .registrationUnsupported: return "The Splice authorization server did not advertise dynamic client registration."
        case .http(let code, let value): return "Splice OAuth failed (HTTP \(code)): \(value)"
        }
    }
}

actor VisionSpliceOAuthCoordinator {
    static let shared = VisionSpliceOAuthCoordinator()
    private var pending: VisionSpliceOAuthSession?
    private let redirectURI = "lemmingsstudio://splice/callback"

    func authorizationURL(resourceEndpoint: URL) async throws -> URL {
        let resourceMetadataURL = URL(string: "https://mcp.splice.com/.well-known/oauth-protected-resource/mcp")!
        let resource: VisionOAuthProtectedResourceMetadata = try await getJSON(resourceMetadataURL)
        guard let serverText = resource.authorization_servers?.first, let server = URL(string: serverText) else {
            throw VisionSpliceOAuthError.metadata("No authorization server advertised")
        }
        let metadataURL = server.appendingPathComponent(".well-known/oauth-authorization-server")
        let metadata: VisionOAuthAuthorizationMetadata = try await getJSON(metadataURL)
        guard let authorizationEndpoint = URL(string: metadata.authorization_endpoint),
              let tokenEndpoint = URL(string: metadata.token_endpoint) else {
            throw VisionSpliceOAuthError.metadata("Invalid authorization or token endpoint")
        }

        let clientID: String
        if let stored = VisionCredentialStore.get(account: "splice-oauth-client-id"), !stored.isEmpty {
            clientID = stored
        } else {
            guard let registrationText = metadata.registration_endpoint, let registration = URL(string: registrationText) else {
                throw VisionSpliceOAuthError.registrationUnsupported
            }
            let body: [String: Any] = [
                "client_name": "LemmingsStudio visionOS",
                "redirect_uris": [redirectURI],
                "grant_types": ["authorization_code", "refresh_token"],
                "response_types": ["code"],
                "token_endpoint_auth_method": "none"
            ]
            let registered: VisionOAuthRegistrationResponse = try await postJSON(registration, body: body)
            clientID = registered.client_id
            try VisionCredentialStore.set(clientID, account: "splice-oauth-client-id")
        }

        let verifier = randomURLSafe(bytes: 48)
        let challengeData = Data(SHA256.hash(data: Data(verifier.utf8)))
        let challenge = challengeData.base64URLEncodedString()
        let state = randomURLSafe(bytes: 24)
        pending = VisionSpliceOAuthSession(clientID: clientID, tokenEndpoint: tokenEndpoint, redirectURI: redirectURI, codeVerifier: verifier, state: state)

        var components = URLComponents(url: authorizationEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "resource", value: resourceEndpoint.absoluteString)
        ]
        guard let url = components.url else { throw VisionSpliceOAuthError.metadata("Could not build authorization URL") }
        return url
    }

    func handleCallback(_ callback: URL) async throws {
        guard let session = pending else { throw VisionSpliceOAuthError.missingCode }
        let components = URLComponents(url: callback, resolvingAgainstBaseURL: false)
        let items = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).compactMap { item in item.value.map { (item.name, $0) } })
        guard items["state"] == session.state else { throw VisionSpliceOAuthError.stateMismatch }
        guard let code = items["code"], !code.isEmpty else { throw VisionSpliceOAuthError.missingCode }

        var request = URLRequest(url: session.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let fields = [
            "grant_type": "authorization_code",
            "code": code,
            "client_id": session.clientID,
            "redirect_uri": session.redirectURI,
            "code_verifier": session.codeVerifier
        ]
        request.httpBody = fields.map { key, value in
            "\(urlEncode(key))=\(urlEncode(value))"
        }.sorted().joined(separator: "&").data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        let codeValue = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(codeValue) else {
            throw VisionSpliceOAuthError.http(codeValue, String(data: data, encoding: .utf8) ?? "Unknown token error")
        }
        let token = try JSONDecoder().decode(VisionOAuthTokenResponse.self, from: data)
        try VisionCredentialStore.set(token.access_token, account: "splice-oauth-access-token")
        if let refresh = token.refresh_token { try VisionCredentialStore.set(refresh, account: "splice-oauth-refresh-token") }
        pending = nil
    }

    private func getJSON<T: Decodable>(_ url: URL) async throws -> T {
        let (data, response) = try await URLSession.shared.data(from: url)
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(code) else { throw VisionSpliceOAuthError.http(code, String(data: data, encoding: .utf8) ?? "Metadata request failed") }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func postJSON<T: Decodable>(_ url: URL, body: [String: Any]) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(code) else { throw VisionSpliceOAuthError.http(code, String(data: data, encoding: .utf8) ?? "Registration failed") }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func randomURLSafe(bytes: Int) -> String {
        var data = Data(count: bytes)
        _ = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, bytes, $0.baseAddress!) }
        return data.base64URLEncodedString()
    }

    private func urlEncode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "+&="))) ?? text
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

extension VisionStudioModel {
    func beginSpliceLogin() {
        spliceMCP.statusText = "Preparing secure Splice login…"
        Task {
            do {
                let endpoint = URL(string: spliceMCP.endpoint) ?? URL(string: "https://mcp.splice.com/mcp")!
                let authURL = try await VisionSpliceOAuthCoordinator.shared.authorizationURL(resourceEndpoint: endpoint)
                spliceMCP.statusText = "Complete Splice sign-in in Safari, then return to LemmingsStudio."
                statusMessage = spliceMCP.statusText
                await UIApplication.shared.open(authURL)
            } catch {
                spliceMCP.statusText = "Splice login could not start: \(error.localizedDescription)"
                statusMessage = spliceMCP.statusText
            }
        }
    }

    func handleAppURL(_ url: URL) {
        guard url.scheme?.lowercased() == "lemmingsstudio", url.host?.lowercased() == "splice" else {
            openProject(at: url)
            return
        }
        spliceMCP.statusText = "Completing Splice login…"
        Task {
            do {
                try await VisionSpliceOAuthCoordinator.shared.handleCallback(url)
                spliceMCP.statusText = "Splice login complete. Connecting MCP…"
                refreshSpliceMCPTools()
            } catch {
                spliceMCP.statusText = "Splice login failed: \(error.localizedDescription)"
                statusMessage = spliceMCP.statusText
            }
        }
    }
}
