import Foundation

/// Any JSON value. Records are kept as JSON objects so fields this app doesn't know
/// (from older versions or plugins) survive a round trip untouched.
enum JSONValue: Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    var string: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    /// Numbers, or numeric strings: plugins and older forms sometimes store a year as "1999".
    var double: Double? {
        switch self {
        case .number(let n): return n
        case .string(let s): return Double(s.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }

    var int: Int? { double.flatMap { $0.isFinite ? Int($0) : nil } }

    var bool: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    var array: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    var object: [String: JSONValue]? {
        if case .object(let o) = self { return o }
        return nil
    }

    var isNull: Bool { self == .null }

    /// JavaScript truthiness, for porting `if (x)` checks faithfully.
    var isTruthy: Bool {
        switch self {
        case .null: return false
        case .bool(let b): return b
        case .number(let n): return n != 0 && !n.isNaN
        case .string(let s): return !s.isEmpty
        case .array, .object: return true
        }
    }

    /// What `${value}` prints in JavaScript, used by the sync fingerprint.
    var templateString: String {
        switch self {
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .number(let n):
            if n.rounded() == n, abs(n) < 1e15 { return String(Int64(n)) }
            return String(n)
        case .string(let s): return s
        case .array(let a): return a.map(\.templateString).joined(separator: ",")
        case .object: return "[object Object]"
        }
    }
}

extension JSONValue: Codable {
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? c.decode(Double.self) {
            self = .number(n)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([JSONValue].self) {
            self = .array(a)
        } else {
            self = .object(try c.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n):
            // Whole numbers go out as integers, as JSON.stringify writes them.
            if n.rounded() == n, abs(n) < 1e15 { try c.encode(Int64(n)) } else { try c.encode(n) }
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByBooleanLiteral, ExpressibleByNilLiteral,
    ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
    init(stringLiteral value: String) { self = .string(value) }
    init(booleanLiteral value: Bool) { self = .bool(value) }
    init(nilLiteral: ()) { self = .null }
    init(integerLiteral value: Int) { self = .number(Double(value)) }
    init(floatLiteral value: Double) { self = .number(value) }
    init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}

extension JSONValue {
    init(_ string: String?) { self = string.map(JSONValue.string) ?? .null }
    init(_ number: Double?) { self = number.map(JSONValue.number) ?? .null }
    init(_ number: Int?) { self = number.map { .number(Double($0)) } ?? .null }
    init(_ strings: [String]) { self = .array(strings.map(JSONValue.string)) }
}

/// Timestamps exactly as JavaScript's `toISOString()` writes them (the format synced documents
/// already use), so they also compare correctly as strings, as the watch does.
enum Timestamp {
    private static let withMillis: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func string(_ date: Date = Date()) -> String { withMillis.string(from: date) }

    static func now() -> String { string() }

    static func date(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        return withMillis.date(from: string) ?? plain.date(from: string)
    }

    /// `Date.parse` in milliseconds, nil where JavaScript would give NaN.
    static func millis(_ string: String?) -> Double? {
        date(string).map { $0.timeIntervalSince1970 * 1000 }
    }
}

enum RecordID {
    /// 24 lowercase hex characters, the id format synced documents already use.
    static func make() -> String {
        var bytes = [UInt8](repeating: 0, count: 12)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
