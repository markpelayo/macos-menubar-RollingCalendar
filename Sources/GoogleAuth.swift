import AppKit
import CryptoKit
import Foundation
import Network
import Security

enum AuthError: LocalizedError {
    case notConfigured
    case cancelled
    case server(String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Google sign-in isn't set up yet. Use “Set Up Google Sign-In…” first."
        case .cancelled: return "Sign-in was cancelled."
        case .server(let m): return m
        case .badResponse: return "Unexpected response from Google."
        }
    }
}

/// OAuth 2.0 for installed apps (PKCE + loopback redirect).
/// The user sees a normal Google login page in their browser; the app never
/// handles the password. The refresh token is kept in the login Keychain.
final class GoogleAuth {

    static let shared = GoogleAuth()
    private init() {}

    private let scope = "https://www.googleapis.com/auth/calendar.readonly"
    private let authEndpoint = "https://accounts.google.com/o/oauth2/v2/auth"
    private let tokenEndpoint = "https://oauth2.googleapis.com/token"
    private let keychainService = "io.github.macos-menubar-rollingcalendar"
    private let keychainAccount = "google-refresh-token"

    // MARK: Client credentials (from the OAuth client you create once)

    var clientID: String? {
        let v = UserDefaults.standard.string(forKey: "googleClientID")
        return (v?.isEmpty == false) ? v : nil
    }

    var clientSecret: String? {
        let v = UserDefaults.standard.string(forKey: "googleClientSecret")
        return (v?.isEmpty == false) ? v : nil
    }

    func setClient(id: String?, secret: String?) {
        let d = UserDefaults.standard
        let id = id?.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = secret?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id, !id.isEmpty { d.set(id, forKey: "googleClientID") } else { d.removeObject(forKey: "googleClientID") }
        if let secret, !secret.isEmpty { d.set(secret, forKey: "googleClientSecret") } else { d.removeObject(forKey: "googleClientSecret") }
    }

    var isConfigured: Bool { clientID != nil }
    var isSignedIn: Bool { refreshToken != nil }
    var signedInAccount: String? { UserDefaults.standard.string(forKey: "googleAccount") }

    // MARK: In-flight state

    private var accessToken: String?
    private var accessTokenExpiry: Date?
    private var listener: NWListener?
    private var verifier: String?
    private var expectedState: String?
    private var redirectURI: String?
    private var completion: ((Result<Void, Error>) -> Void)?
    private var timeoutWork: DispatchWorkItem?

    // MARK: Sign in / out

    func signIn(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let clientID else { completion(.failure(AuthError.notConfigured)); return }
        // Abandon any sign-in already in flight, telling its caller.
        if let old = self.completion {
            self.completion = nil
            DispatchQueue.main.async { old(.failure(AuthError.cancelled)) }
        }
        cancelPending()
        self.completion = completion

        let verifier = Self.randomURLSafeString(64)
        self.verifier = verifier
        let challenge = Self.codeChallenge(for: verifier)
        let state = Self.randomURLSafeString(24)
        expectedState = state

        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            // Note: the argument label is `on:`, not `port:`.
            let listener = try NWListener(using: params, on: .any)
            self.listener = listener

            listener.newConnectionHandler = { [weak self] conn in
                conn.start(queue: .main)
                conn.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, _, _ in
                    let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    // Browsers also open speculative sockets and ask for /favicon.ico.
                    // Ignore anything that isn't the OAuth redirect, and leave the
                    // listener running so the real one still lands.
                    guard request.contains("code=") || request.contains("error=") else {
                        conn.cancel()
                        return
                    }
                    self?.respond(on: conn, request: request)
                    self?.handle(request: request)
                }
            }

            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    guard let port = self.listener?.port else { return }
                    let redirect = "http://127.0.0.1:\(port.rawValue)"
                    self.redirectURI = redirect
                    self.openBrowser(clientID: clientID, redirect: redirect,
                                     challenge: challenge, state: self.expectedState ?? "")
                case .failed(let err):
                    self.finish(.failure(err))
                default:
                    break
                }
            }
            listener.start(queue: .main)

            // Don't leave the local listener open forever.
            let work = DispatchWorkItem { [weak self] in self?.finish(.failure(AuthError.cancelled)) }
            timeoutWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 300, execute: work)

        } catch {
            finish(.failure(error))
        }
    }

    func signOut() {
        deleteRefreshToken()
        UserDefaults.standard.removeObject(forKey: "googleAccount")
        accessToken = nil
        accessTokenExpiry = nil
    }

    /// Forget the OAuth client too (full reset).
    func forgetClient() {
        signOut()
        setClient(id: nil, secret: nil)
    }

    // MARK: Access tokens

    func withAccessToken(_ completion: @escaping (Result<String, Error>) -> Void) {
        if let token = accessToken, let exp = accessTokenExpiry, exp > Date().addingTimeInterval(60) {
            completion(.success(token))
            return
        }
        guard let clientID, let refresh = refreshToken else {
            completion(.failure(AuthError.notConfigured))
            return
        }
        var form = ["client_id": clientID, "refresh_token": refresh, "grant_type": "refresh_token"]
        if let clientSecret { form["client_secret"] = clientSecret }

        post(form) { [weak self] result in
            switch result {
            case .failure(let e):
                completion(.failure(e))
            case .success(let json):
                guard let token = json["access_token"] as? String else {
                    // Refresh token revoked or expired — force a fresh sign-in.
                    self?.signOut()
                    completion(.failure(AuthError.server("Google sign-in expired. Please sign in again.")))
                    return
                }
                let ttl = (json["expires_in"] as? Double) ?? 3300
                self?.accessToken = token
                self?.accessTokenExpiry = Date().addingTimeInterval(ttl)
                completion(.success(token))
            }
        }
    }

    // MARK: - Private

    private func openBrowser(clientID: String, redirect: String, challenge: String, state: String) {
        var comps = URLComponents(string: authEndpoint)!
        comps.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirect),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        guard let url = comps.url else { finish(.failure(AuthError.badResponse)); return }
        NSWorkspace.shared.open(url)
    }

    private func respond(on conn: NWConnection, request: String) {
        let ok = request.contains("code=")
        let title = ok ? "Signed in ✓" : "Sign-in failed"
        let detail = ok ? "You can close this tab and go back to Rolling Calendar."
                        : "Something went wrong. Try “Sign in with Google…” again."
        let body = """
        <!doctype html><meta charset="utf-8">
        <body style="font-family:-apple-system,system-ui;text-align:center;margin-top:18vh;color:#222">
        <h2>\(title)</h2><p>\(detail)</p></body>
        """
        let head = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r

        """
        let data = Data((head + body).utf8)
        conn.send(content: data, completion: .contentProcessed { _ in conn.cancel() })
    }

    private func handle(request: String) {
        // First line looks like:  GET /?state=…&code=…&scope=… HTTP/1.1
        guard let line = request.split(separator: "\r\n", maxSplits: 1).first,
              let path = line.split(separator: " ").dropFirst().first,
              let comps = URLComponents(string: "http://127.0.0.1\(path)") else {
            finish(.failure(AuthError.badResponse))
            return
        }
        let items = comps.queryItems ?? []
        func value(_ n: String) -> String? { items.first(where: { $0.name == n })?.value }

        if let err = value("error") {
            finish(.failure(AuthError.server("Google returned “\(err)”.")))
            return
        }
        guard let code = value("code"), let verifier,
              let redirect = redirectURI, let clientID,
              value("state") == expectedState else {
            finish(.failure(AuthError.badResponse))
            return
        }

        var form = [
            "code": code,
            "client_id": clientID,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirect
        ]
        if let clientSecret { form["client_secret"] = clientSecret }

        post(form) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let e):
                self.finish(.failure(e))
            case .success(let json):
                guard let refresh = json["refresh_token"] as? String else {
                    self.finish(.failure(AuthError.server(
                        "Google didn't return a refresh token. Remove the app's access at "
                        + "myaccount.google.com/permissions and sign in again.")))
                    return
                }
                self.saveRefreshToken(refresh)
                if let access = json["access_token"] as? String {
                    self.accessToken = access
                    self.accessTokenExpiry = Date().addingTimeInterval((json["expires_in"] as? Double) ?? 3300)
                }
                self.finish(.success(()))
            }
        }
    }

    private func post(_ form: [String: String], done: @escaping (Result<[String: Any], Error>) -> Void) {
        var req = URLRequest(url: URL(string: tokenEndpoint)!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data(form.map { k, v in
            "\(Self.formEncode(k))=\(Self.formEncode(v))"
        }.joined(separator: "&").utf8)
        req.timeoutInterval = 30

        URLSession.shared.dataTask(with: req) { data, _, error in
            DispatchQueue.main.async {
                if let error { done(.failure(error)); return }
                guard let data,
                      let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                    done(.failure(AuthError.badResponse)); return
                }
                if let err = json["error"] as? String {
                    let desc = json["error_description"] as? String
                    done(.failure(AuthError.server("Google: \(desc ?? err)")))
                    return
                }
                done(.success(json))
            }
        }.resume()
    }

    private func finish(_ result: Result<Void, Error>) {
        let cb = completion
        completion = nil
        cancelPending()
        if let cb { DispatchQueue.main.async { cb(result) } }
    }

    private func cancelPending() {
        timeoutWork?.cancel()
        timeoutWork = nil
        // Clear the handlers first: they capture the listener, so leaving them
        // in place would keep it alive after cancel().
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
        verifier = nil
        expectedState = nil
        redirectURI = nil
    }

    // MARK: PKCE helpers

    private static func randomURLSafeString(_ length: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var out = ""
        for _ in 0..<length { out.append(chars[Int.random(in: 0..<chars.count)]) }
        return out
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func formEncode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    // MARK: Keychain

    /// Cached so that `isSignedIn` — consulted on every menu open and every
    /// refresh tick — doesn't hit the Keychain (which can block on a prompt).
    private var cachedRefresh: String??

    private var refreshToken: String? {
        if let cachedRefresh { return cachedRefresh }
        let value = readRefreshTokenFromKeychain()
        cachedRefresh = .some(value)
        return value
    }

    private func readRefreshTokenFromKeychain() -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = withUnsafeMutablePointer(to: &item) { SecItemCopyMatching(query as CFDictionary, $0) }
        query.removeAll()
        if status == errSecSuccess, let data = item as? Data, let s = String(data: data, encoding: .utf8) {
            return s
        }
        // Fallback for environments where the Keychain is unavailable.
        return UserDefaults.standard.string(forKey: "googleRefreshTokenFallback")
    }

    private func saveRefreshToken(_ token: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(token.utf8)
        let status = SecItemAdd(add as CFDictionary, nil)
        if status != errSecSuccess {
            // Keychain unavailable (rare). Better than losing the session, but
            // this file is not encrypted — noted in the README.
            NSLog("RollingCalendar: Keychain write failed (\(status)); falling back to defaults.")
            UserDefaults.standard.set(token, forKey: "googleRefreshTokenFallback")
        }
        cachedRefresh = .some(token)
    }

    private func deleteRefreshToken() {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(base as CFDictionary)
        UserDefaults.standard.removeObject(forKey: "googleRefreshTokenFallback")
        cachedRefresh = .some(nil)
    }
}
