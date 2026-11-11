/// The visual and structural style of a pipe.
public enum PipeKind: String, Codable, Sendable, CaseIterable {
    /// A smooth curve between the two ports.
    case bezier
    /// Two straight runs meeting at a corner, or one straight run when the
    /// ports face each other.
    case corner
    /// Straight runs meeting in a circular room.
    case roomSmall
    case roomMedium
    case roomLarge

    public var isRoom: Bool {
        switch self {
        case .roomSmall, .roomMedium, .roomLarge: true
        case .bezier, .corner: false
        }
    }
}

/// A tube joining two ports of one tile.
///
/// A pipe has no direction, so its ports are stored in sorted order and
/// `Pipe(kind, a: x, b: y)` equals `Pipe(kind, a: y, b: x)`.
public struct Pipe: Hashable, Sendable, Codable {
    public let kind: PipeKind
    public let a: Port
    public let b: Port

    public init(_ kind: PipeKind, a: Port, b: Port) {
        self.kind = kind
        self.a = min(a, b)
        self.b = max(a, b)
    }

    private enum CodingKeys: String, CodingKey {
        case kind, a, b
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            try container.decode(PipeKind.self, forKey: .kind),
            a: try container.decode(Port.self, forKey: .a),
            b: try container.decode(Port.self, forKey: .b)
        )
    }

    public func touches(_ port: Port) -> Bool {
        a == port || b == port
    }

    /// The far end of the pipe, or nil if `port` is not one of its ends.
    public func otherEnd(from port: Port) -> Port? {
        if port == a { return b }
        if port == b { return a }
        return nil
    }
}
