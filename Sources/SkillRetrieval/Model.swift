import Foundation

/// A machine-checkable precondition a skill declares about the environment it expects.
/// Prose preconditions ("make sure you are in an SPM package") cannot be checked by a
/// resolver; these can.
public enum Precondition: Hashable, Sendable, CustomStringConvertible {
    case fileExists(String)
    case toolAvailable(String)
    case minimumToolVersion(tool: String, version: Int)

    public func isSatisfied(in env: Environment) -> Bool {
        switch self {
        case .fileExists(let path):
            return env.files.contains(path)
        case .toolAvailable(let tool):
            return env.toolVersions[tool] != nil
        case .minimumToolVersion(let tool, let version):
            guard let have = env.toolVersions[tool] else { return false }
            return have >= version
        }
    }

    public var description: String {
        switch self {
        case .fileExists(let p): return "file \(p)"
        case .toolAvailable(let t): return "tool \(t)"
        case .minimumToolVersion(let t, let v): return "\(t) >= \(v)"
        }
    }
}

/// What the resolver is allowed to know about the caller's environment when it resolves.
public struct Environment: Hashable, Sendable {
    public var files: Set<String>
    public var toolVersions: [String: Int]

    public init(files: Set<String> = [], toolVersions: [String: Int] = [:]) {
        self.files = files
        self.toolVersions = toolVersions
    }
}

/// One entry in a skills library. `family` is the capability family ("release", "test", ...);
/// two skills in the same family are *siblings*, which is exactly where retrieval goes wrong.
public struct Skill: Identifiable, Hashable, Sendable {
    public let id: String
    public let family: String
    public let title: String
    public let summary: String
    public let keywords: [String]
    public let version: Int
    public let updatedAt: Date
    public let preconditions: [Precondition]
    public let supersededBy: String?

    public init(
        id: String,
        family: String,
        title: String,
        summary: String,
        keywords: [String],
        version: Int = 1,
        updatedAt: Date,
        preconditions: [Precondition] = [],
        supersededBy: String? = nil
    ) {
        self.id = id
        self.family = family
        self.title = title
        self.summary = summary
        self.keywords = keywords
        self.version = version
        self.updatedAt = updatedAt
        self.preconditions = preconditions
        self.supersededBy = supersededBy
    }

    public var isSuperseded: Bool { supersededBy != nil }

    /// The text the lexical resolver indexes. Keywords are repeated so they weigh more than prose.
    var indexedText: String {
        ([title, summary] + keywords + keywords).joined(separator: " ")
    }
}

/// An immutable, id-addressable skills library.
public struct SkillCatalog: Sendable {
    public let skills: [Skill]
    private let byID: [String: Skill]

    public init(_ skills: [Skill]) {
        self.skills = skills.sorted { $0.id < $1.id }
        var map: [String: Skill] = [:]
        for s in skills { map[s.id] = s }
        self.byID = map
    }

    public subscript(id: String) -> Skill? { byID[id] }

    public var count: Int { skills.count }

    public func siblings(of skill: Skill) -> [Skill] {
        skills.filter { $0.family == skill.family && $0.id != skill.id }
    }

    public var families: [String] {
        Array(Set(skills.map(\.family))).sorted()
    }
}
