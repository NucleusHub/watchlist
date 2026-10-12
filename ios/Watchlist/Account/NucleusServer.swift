import Foundation

/// A Nucleus ID server: where it is, and the code a private one asks for.
struct NucleusServer: Codable, Hashable {
    static let defaultDiscoveryPath = "/api/v1/oauth/metadata"

    var scheme = "https"
    var host: String
    var port: Int?
    var discoveryPath = NucleusServer.defaultDiscoveryPath
    var code: String?

    var origin: URL {
        var c = URLComponents()
        c.scheme = scheme
        c.host = host
        c.port = port
        return c.url!
    }

    var discoveryURL: URL { URL(string: origin.absoluteString + discoveryPath)! }

    /// The server field: `host`, `host:port` or a full URL. A scheme or port in the text wins; a path is ignored.
    static func parse(_ text: String, scheme: String = "https", port: Int? = nil,
                      discoveryPath: String = defaultDiscoveryPath) throws -> NucleusServer {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ServerProblem.badAddress }
        let full = trimmed.contains("://") ? trimmed : "\(scheme)://\(trimmed)"
        guard let c = URLComponents(string: full), let host = c.host?.lowercased(), !host.isEmpty,
              let s = c.scheme?.lowercased(), s == "http" || s == "https" else { throw ServerProblem.badAddress }
        let path = discoveryPath.trimmingCharacters(in: .whitespaces)
        let server = NucleusServer(scheme: s, host: host, port: c.port ?? port,
                                   discoveryPath: path.isEmpty ? defaultDiscoveryPath : (path.hasPrefix("/") ? path : "/" + path))
        // URLComponents accepts some hosts it then can't turn into a URL.
        guard URL(string: server.origin.absoluteString + server.discoveryPath) != nil else { throw ServerProblem.badAddress }
        return server
    }

    static func isCode(_ text: String) -> Bool {
        text.range(of: "^nucleus[0-9A-Za-z]{32}home$", options: .regularExpression) != nil
    }

    /// `com.nucleushome.watchlist://server?scheme=…&host=…&port=…&path=…&code=…`
    static func setup(from url: URL) throws -> NucleusServer {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        return try setup(scheme: value("scheme"), host: value("host"), port: value("port"), path: value("path"), code: value("code"))
    }

    /// A `.nucleusserver` file: the link's fields as JSON.
    static func setup(fromFile data: Data) throws -> NucleusServer {
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw ServerProblem.badSetup }
        let port = (o["port"] as? Int).map(String.init) ?? o["port"] as? String
        return try setup(scheme: o["scheme"] as? String, host: o["host"] as? String, port: port,
                         path: o["path"] as? String, code: o["code"] as? String)
    }

    private static func setup(scheme: String?, host: String?, port: String?, path: String?, code: String?) throws -> NucleusServer {
        let scheme = scheme?.lowercased() ?? "https"
        guard let host, !host.isEmpty, !host.contains("/"), !host.contains(":"), scheme == "http" || scheme == "https"
        else { throw ServerProblem.badSetup }
        var portNumber: Int?
        if let port, !port.isEmpty {
            guard let p = Int(port), (1...65535).contains(p) else { throw ServerProblem.badSetup }
            portNumber = p
        }
        var server: NucleusServer
        do {
            server = try parse(host, scheme: scheme, port: portNumber, discoveryPath: path ?? defaultDiscoveryPath)
        } catch {
            throw ServerProblem.badSetup
        }
        if let code = code?.trimmingCharacters(in: .whitespacesAndNewlines), !code.isEmpty {
            guard isCode(code) else { throw ServerProblem.badCode }
            server.code = code
        }
        return server
    }
}

/// Why a server can't be used, as the sign-in sheet says it.
enum ServerProblem: Error, Equatable {
    case badAddress, unreachable, untrusted, needsHTTPS, notNucleus, badCode, codeRejected, badSetup, tooManyTries

    var message: LocalizedStringResource {
        switch self {
        case .badAddress: "Enter a server address."
        case .unreachable: "Couldn't reach this server."
        case .untrusted: "This server's certificate isn't trusted."
        case .needsHTTPS: "This server needs https."
        case .notNucleus: "This isn't a Nucleus ID server."
        case .badCode: "This isn't a Nucleus server code."
        case .codeRejected: "The server didn't accept this code."
        case .badSetup: "This isn't a Nucleus server setup."
        case .tooManyTries: "Too many tries. Wait a minute and try again."
        }
    }
}
