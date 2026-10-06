import AuthenticationServices
import CryptoKit
import Foundation
import NucleusUI
import Observation
import UIKit

/// Signing in with a Nucleus ID account: OAuth 2 authorization code with PKCE, as the
/// public `watchlist` client.
@MainActor
@Observable
final class NucleusID: NSObject {
    nonisolated static let origin = URL(string: "https://nucleus-home.dev")!
    nonisolated static let clientID = "watchlist"
    nonisolated static let redirectURI = "com.nucleushome.watchlist:/oauth"
    nonisolated static let callbackScheme = "com.nucleushome.watchlist"
    nonisolated static let scope = "profile data"
    nonisolated static var privacyURL: URL { origin.appending(path: "privacy") }
    nonisolated static var deleteAccountURL: URL { origin.appending(path: "account/delete") }

    enum Mode { case keep, clean }

    enum AuthError: Equatable {
        case expired, offline, cancelled
        case failed(String)
    }

    private(set) var session: NucleusSession?
    private(set) var signingIn = false
    var error: AuthError?

    var isSignedIn: Bool { session != nil }
    var user: NucleusSession.User? { session?.user }

    @ObservationIgnored var onSignedIn: ((Mode) async -> Void)?
    @ObservationIgnored var onSignedOut: ((_ clean: Bool) async -> Void)?
    /// The account ended the session (refresh token revoked); nothing can be synced any more.
    @ObservationIgnored var onExpired: (() -> Void)?
    @ObservationIgnored private var refreshing: Task<NucleusSession, Error>?
    @ObservationIgnored private var webSession: ASWebAuthenticationSession?

    private static let refreshMargin: TimeInterval = 60

    override init() {
        session = NucleusSession.load()
        super.init()
    }

    /// Checks a stored session still works, refreshing it if the access token has lapsed.
    func validate() async {
        guard session != nil else { return }
        do {
            let (data, response) = try await authorized(URLRequest(url: Self.origin.appending(path: "api/v1/oauth/userinfo")))
            if response.statusCode == 200, let user = Self.user(from: data), var s = session {
                s.user = user
                session = s
                s.save()
                Self.applyAppearance(from: data)
            }
        } catch {}
    }

    // MARK: Signing in and out

    func signIn(mode: Mode = .keep) async {
        guard !signingIn else { return }
        signingIn = true
        error = nil
        defer { signingIn = false }

        let verifier = Self.randomToken(48)
        let state = Self.randomToken(16)
        var c = URLComponents(url: Self.origin.appending(path: "authorize"), resolvingAgainstBaseURL: false)!
        c.queryItems = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: Self.clientID),
            .init(name: "redirect_uri", value: Self.redirectURI),
            .init(name: "scope", value: Self.scope),
            .init(name: "state", value: state),
            .init(name: "code_challenge", value: Self.challenge(verifier)),
            .init(name: "code_challenge_method", value: "S256"),
        ]

        do {
            let callback = try await authenticate(url: c.url!)
            let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if let err = items.first(where: { $0.name == "error" })?.value {
                if err == "access_denied" { return }
                throw Failure.server(err)
            }
            guard items.first(where: { $0.name == "state" })?.value == state,
                  let code = items.first(where: { $0.name == "code" })?.value else { throw Failure.server("invalid_state") }

            var tokens = try await tokenRequest([
                "grant_type": "authorization_code", "code": code,
                "redirect_uri": Self.redirectURI, "code_verifier": verifier,
            ])
            var request = URLRequest(url: Self.origin.appending(path: "api/v1/oauth/userinfo"))
            request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
            let (data, _) = try await URLSession.shared.data(for: request)
            if let user = Self.user(from: data) { tokens.user = user }
            Self.applyAppearance(from: data)
            tokens.save()
            session = tokens
            await onSignedIn?(mode)
        } catch let e as ASWebAuthenticationSessionError where e.code == .canceledLogin {
            return
        } catch {
            self.error = Self.classify(error)
        }
    }

    func signOut(clean: Bool) async {
        await onSignedOut?(clean)
        if let refresh = session?.refreshToken {
            // Fire and forget: signing out works offline too.
            Task.detached { _ = try? await Self.post("api/v1/oauth/revoke", ["client_id": Self.clientID, "token": refresh]) }
        }
        NucleusSession.clear()
        session = nil
        refreshing = nil
        NucleusTheme.shared.account = nil
    }

    private func expire() async {
        onExpired?()
        NucleusSession.clear()
        session = nil
        NucleusTheme.shared.account = nil
        error = .expired
    }

    // MARK: Account appearance

    /// Sets the account's theme, which apps start with; `applyToApps` makes every app take it over its own.
    func setAccountAccent(_ accent: NucleusAccent, applyToApps: Bool) async throws {
        var req = URLRequest(url: Self.origin.appending(path: "api/v1/oauth/appearance"))
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let appearance: JSONValue = .object(accent.customHex.map { ["accent": "custom", "customAccent": .string($0)] } ?? ["accent": .string(accent.id)])
        req.httpBody = try JSONEncoder().encode(JSONValue.object(["appearance": appearance, "applyToApps": .bool(applyToApps)]))
        let (data, response) = try await authorized(req)
        guard response.statusCode == 200 else { throw Failure.server(Self.message(from: data) ?? "HTTP \(response.statusCode)") }
        Self.applyAppearance(from: data)
    }

    /// The `appearance` of a userinfo or appearance response, or null when the account never set one.
    private static func applyAppearance(from data: Data) {
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let value = o["appearance"] else { return }
        NucleusTheme.shared.account = NucleusAccountTheme(json: value as? [String: Any])
    }

    private static func message(from data: Data) -> String? {
        let o = (try? JSONDecoder().decode(JSONValue.self, from: data))?.object
        return o?["error"]?.object?["message"]?.string ?? o?["message"]?.string
    }

    // MARK: Authorized requests

    /// A request with a fresh bearer token; on 401 the token is refreshed once and the request retried.
    func authorized(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var req = request
        req.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        var (data, response) = try await Self.send(req)
        if response.statusCode == 401 {
            req.setValue("Bearer \(try await refresh().accessToken)", forHTTPHeaderField: "Authorization")
            (data, response) = try await Self.send(req)
        }
        return (data, response)
    }

    private func accessToken() async throws -> String {
        guard let s = session else { throw Failure.signedOut }
        if s.expiresDate.timeIntervalSinceNow > Self.refreshMargin { return s.accessToken }
        return try await refresh().accessToken
    }

    /// One refresh at a time: refresh tokens rotate, and reusing an old one revokes the whole grant.
    private func refresh() async throws -> NucleusSession {
        if let refreshing { return try await refreshing.value }
        guard let current = session else { throw Failure.signedOut }
        let task = Task { () throws -> NucleusSession in
            var next = try await self.tokenRequest(["grant_type": "refresh_token", "refresh_token": current.refreshToken])
            next.user = current.user
            return next
        }
        refreshing = task
        defer { refreshing = nil }
        do {
            let next = try await task.value
            next.save()
            session = next
            return next
        } catch Failure.server("invalid_grant") {
            await expire()
            throw Failure.signedOut
        }
    }

    // MARK: Plumbing

    enum Failure: Error, Equatable {
        case signedOut
        case server(String)
    }

    private func tokenRequest(_ fields: [String: String]) async throws -> NucleusSession {
        var body = fields
        body["client_id"] = Self.clientID
        let (data, response) = try await Self.post("api/v1/oauth/token", body)
        let json = (try? JSONDecoder().decode(JSONValue.self, from: data))?.object ?? [:]
        guard response.statusCode == 200, let access = json["access_token"]?.string else {
            throw Failure.server(json["error"]?.string ?? "HTTP \(response.statusCode)")
        }
        let expiresIn = json["expires_in"]?.double ?? 3600
        return NucleusSession(
            accessToken: access,
            refreshToken: json["refresh_token"]?.string ?? session?.refreshToken ?? "",
            expiresAt: (Date().timeIntervalSince1970 + expiresIn) * 1000,
            user: session?.user ?? .init(sub: "", handle: "", name: "", email: nil)
        )
    }

    private nonisolated static func post(_ path: String, _ fields: [String: String]) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: origin.appending(path: path))
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = fields.map { "\($0.key)=\(OpenLinks.enc($0.value))" }.joined(separator: "&").data(using: .utf8)
        return try await send(req)
    }

    nonisolated static func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }

    private static func user(from data: Data) -> NucleusSession.User? {
        guard let o = (try? JSONDecoder().decode(JSONValue.self, from: data))?.object, let sub = o["sub"]?.string else { return nil }
        let handle = o["preferred_username"]?.string ?? ""
        return .init(sub: sub, handle: handle, name: o["name"]?.string.flatMap { $0.isEmpty ? nil : $0 } ?? handle, email: o["email"]?.string)
    }

    private static func classify(_ error: Error) -> AuthError {
        if error is URLError { return .offline }
        if case Failure.server(let reason) = error { return .failed(reason) }
        return .failed(error.localizedDescription)
    }

    static func randomToken(_ bytes: Int) -> String {
        var data = Data(count: bytes)
        _ = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, bytes, $0.baseAddress!) }
        return base64URL(data)
    }

    static func challenge(_ verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func authenticate(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: Self.callbackScheme) { callback, error in
                if let callback { continuation.resume(returning: callback) } else { continuation.resume(throwing: error ?? URLError(.unknown)) }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            webSession = session
            session.start()
        }
    }
}

extension NucleusID: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
        }
    }
}
