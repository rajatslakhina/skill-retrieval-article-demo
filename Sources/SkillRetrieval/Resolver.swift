import Foundation

/// Knobs that turn the naive lexical resolver into a hygienic one. Every flag maps to one
/// piece of retrieval hygiene the article argues for; the evaluator measures each one's effect.
public struct ResolutionPolicy: Hashable, Sendable {
    /// Drop skills that declare a `supersededBy`. A superseded skill is still text; it still matches.
    public var excludeSuperseded: Bool
    /// Drop skills whose machine-checkable preconditions fail in the caller's environment.
    public var enforcePreconditions: Bool
    /// Among siblings that scored within `siblingBand` of the top candidate (relative), rank by
    /// how many of their preconditions the environment satisfies, then by version, and only then
    /// by lexical score. Lexical noise between siblings is not evidence; environment fit is.
    public var rerankSiblings: Bool
    public var siblingBand: Double
    /// Return nothing rather than a top candidate below this cosine score. An empty result is a
    /// question back to the human; a low-score wrong skill is a confident mistake.
    public var minimumScore: Double

    public init(
        excludeSuperseded: Bool,
        enforcePreconditions: Bool,
        rerankSiblings: Bool,
        siblingBand: Double = 0.5,
        minimumScore: Double = 0
    ) {
        self.excludeSuperseded = excludeSuperseded
        self.enforcePreconditions = enforcePreconditions
        self.rerankSiblings = rerankSiblings
        self.siblingBand = siblingBand
        self.minimumScore = minimumScore
    }

    /// Rank by text similarity, nothing else. This is what "put SKILL.md files in a folder" gives you.
    public static let naive = ResolutionPolicy(
        excludeSuperseded: false, enforcePreconditions: false, rerankSiblings: false)

    /// All four hygiene rules on.
    public static let hygienic = ResolutionPolicy(
        excludeSuperseded: true, enforcePreconditions: true, rerankSiblings: true, minimumScore: 0.1)
}

public struct Candidate: Hashable, Sendable, Identifiable {
    public let skill: Skill
    public let score: Double
    public var id: String { skill.id }
}

/// A small TF-IDF cosine resolver over the catalog's indexed text. Deliberately ordinary:
/// the point of the demo is not a clever retriever, it is what the policy around an ordinary
/// retriever does to the wrong-sibling rate.
public struct Resolver: Sendable {
    public let catalog: SkillCatalog
    private let vectors: [String: [String: Double]]
    private let idf: [String: Double]

    public init(catalog: SkillCatalog) {
        self.catalog = catalog
        let docs = catalog.skills.map { ($0.id, Resolver.tokenize($0.indexedText)) }
        var df: [String: Int] = [:]
        for (_, tokens) in docs {
            for t in Set(tokens) { df[t, default: 0] += 1 }
        }
        let n = Double(max(docs.count, 1))
        var idf: [String: Double] = [:]
        for (t, c) in df { idf[t] = log(1 + n / Double(c)) }
        self.idf = idf
        var vectors: [String: [String: Double]] = [:]
        for (id, tokens) in docs {
            vectors[id] = Resolver.vector(tokens, idf: idf)
        }
        self.vectors = vectors
    }

    public static func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count > 1 }
    }

    static func vector(_ tokens: [String], idf: [String: Double]) -> [String: Double] {
        var tf: [String: Double] = [:]
        for t in tokens { tf[t, default: 0] += 1 }
        var v: [String: Double] = [:]
        for (t, c) in tf { v[t] = c * (idf[t] ?? log(2.0)) }
        let norm = sqrt(v.values.reduce(0) { $0 + $1 * $1 })
        guard norm > 0 else { return [:] }
        return v.mapValues { $0 / norm }
    }

    static func cosine(_ a: [String: Double], _ b: [String: Double]) -> Double {
        var dot = 0.0
        for (t, x) in a { if let y = b[t] { dot += x * y } }
        return dot
    }

    /// Resolve a query against the catalog under a policy. Returns at most `limit` candidates,
    /// best first. Ordering is fully deterministic.
    public func resolve(
        _ query: String,
        in env: Environment = Environment(),
        policy: ResolutionPolicy = .naive,
        limit: Int = 3
    ) -> [Candidate] {
        let q = Resolver.vector(Resolver.tokenize(query), idf: idf)
        var pool = catalog.skills
        if policy.excludeSuperseded {
            pool = pool.filter { !$0.isSuperseded }
        }
        if policy.enforcePreconditions {
            pool = pool.filter { skill in skill.preconditions.allSatisfy { $0.isSatisfied(in: env) } }
        }
        var scored = pool.map { Candidate(skill: $0, score: Resolver.cosine(q, vectors[$0.id] ?? [:])) }
        // A folder of SKILL.md files has no notion of version: ties fall to directory order.
        scored.sort { a, b in
            if a.score != b.score { return a.score > b.score }
            return a.skill.id < b.skill.id
        }
        if let top = scored.first, top.score < policy.minimumScore {
            return []
        }
        if policy.rerankSiblings, let top = scored.first {
            let floor = top.score * (1 - policy.siblingBand)
            let inBand = scored.filter { $0.skill.family == top.skill.family && $0.score >= floor }
            let rest = scored.filter { c in !inBand.contains { $0.id == c.id } }
            let reranked = inBand.sorted { a, b in
                let sa = a.skill.preconditions.filter { $0.isSatisfied(in: env) }.count
                let sb = b.skill.preconditions.filter { $0.isSatisfied(in: env) }.count
                if sa != sb { return sa > sb }
                if a.skill.version != b.skill.version { return a.skill.version > b.skill.version }
                if a.score != b.score { return a.score > b.score }
                return a.skill.id < b.skill.id
            }
            scored = reranked + rest
        }
        return Array(scored.prefix(max(limit, 0)))
    }
}
