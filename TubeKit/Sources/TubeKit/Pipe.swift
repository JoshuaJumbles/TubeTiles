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
    /// A dead end: one straight run in from a single port, stopping in a
    /// room. Where a path starts or finishes inside a maze.
    case endSmall
    case endMedium
    case endLarge

    /// A room that a pipe passes through, in on one side and out the other.
    public var isRoom: Bool {
        switch self {
        case .roomSmall, .roomMedium, .roomLarge: true
        case .bezier, .corner, .endSmall, .endMedium, .endLarge: false
        }
    }

    /// True for the kinds that use one port instead of two.
    public var isDeadEnd: Bool {
        switch self {
        case .endSmall, .endMedium, .endLarge: true
        case .bezier, .corner, .roomSmall, .roomMedium, .roomLarge: false
        }
    }

    /// The kinds that join two ports.
    public static let throughKinds: [PipeKind] = allCases.filter { !$0.isDeadEnd }
    /// The dead-end kinds, largest first.
    public static let deadEndKinds: [PipeKind] = [.endLarge, .endMedium, .endSmall]
}

/// A tube joining two ports of one tile, or a dead end at a single port.
///
/// A pipe has no direction, so its ports are stored in sorted order and
/// `Pipe(kind, a: x, b: y)` equals `Pipe(kind, a: y, b: x)`. A dead end has
/// one port, held in both `a` and `b`.
public struct Pipe: Hashable, Sendable, Codable {
    public let kind: PipeKind
    public let a: Port
    public let b: Port

    public init(_ kind: PipeKind, a: Port, b: Port) {
        self.kind = kind
        self.a = min(a, b)
        self.b = max(a, b)
    }

    /// A dead end at `port`.
    public init(_ kind: PipeKind, at port: Port) {
        self.init(kind, a: port, b: port)
    }

    public var isDeadEnd: Bool { kind.isDeadEnd }

    /// The ports the pipe uses: one for a dead end, otherwise two.
    public var ports: [Port] { isDeadEnd ? [a] : [a, b] }

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

    /// The far end of the pipe, or nil if `port` is not one of its ends or
    /// the pipe is a dead end with nowhere further to go.
    public func otherEnd(from port: Port) -> Port? {
        if isDeadEnd { return nil }
        if port == a { return b }
        if port == b { return a }
        return nil
    }
}
