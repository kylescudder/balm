import Foundation

/// A direct, untyped reflection of an Atlassian Document Format JSON node.
/// Decode the document into `ADFNode` once, then walk it with `ADFRenderer`.
/// Unknown node types decode successfully and fall through gracefully.
public struct ADFNode: Sendable, Codable {
    public var type: String
    public var text: String?
    public var content: [ADFNode]?
    public var marks: [ADFMark]?
    public var attrs: [String: ADFAttrValue]?

    public init(
        type: String,
        text: String? = nil,
        content: [ADFNode]? = nil,
        marks: [ADFMark]? = nil,
        attrs: [String: ADFAttrValue]? = nil
    ) {
        self.type = type
        self.text = text
        self.content = content
        self.marks = marks
        self.attrs = attrs
    }
}

public struct ADFMark: Sendable, Codable {
    public var type: String
    public var attrs: [String: ADFAttrValue]?

    public init(type: String, attrs: [String: ADFAttrValue]? = nil) {
        self.type = type
        self.attrs = attrs
    }
}

/// Minimal JSON value used for ADF `attrs`. Atlassian ships everything as
/// strings, numbers, or booleans here — anything more exotic round-trips as
/// `.unknown` so decoding never fails.
public enum ADFAttrValue: Sendable, Codable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    case unknown

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode(Int.self) { self = .int(v); return }
        if let v = try? c.decode(Double.self) { self = .double(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        self = .unknown
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null, .unknown: try c.encodeNil()
        }
    }

    public var stringValue: String? {
        if case .string(let v) = self { return v }
        return nil
    }

    public var intValue: Int? {
        switch self {
        case .int(let v): return v
        case .double(let v): return Int(v)
        case .string(let v): return Int(v)
        default: return nil
        }
    }

    public var boolValue: Bool? {
        if case .bool(let v) = self { return v }
        return nil
    }
}

public extension ADFNode {
    /// Decode an ADF document from raw JSON `Data`. Returns nil on empty input.
    static func decode(from data: Data) throws -> ADFNode? {
        guard !data.isEmpty else { return nil }
        return try JSONDecoder().decode(ADFNode.self, from: data)
    }
}
