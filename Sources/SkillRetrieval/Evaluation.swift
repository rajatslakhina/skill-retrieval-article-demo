import Foundation

/// One retrieval benchmark case: what the agent asked, what its environment looked like,
/// and which skill a human says it should have been handed.
public struct BenchmarkCase: Identifiable, Hashable, Sendable {
    public let id: String
    public let query: String
    public let environment: Environment
    public let expectedSkillID: String

    public init(id: String, query: String, environment: Environment, expectedSkillID: String) {
        self.id = id
        self.query = query
        self.environment = environment
        self.expectedSkillID = expectedSkillID
    }
}

/// How a single case resolved, classified the way a retrieval system should be graded.
public enum Outcome: String, Hashable, Sendable, CaseIterable {
    /// Top-1 was the expected skill.
    case hit
    /// Top-1 was in the expected skill's family but was not the expected skill. The dangerous one:
    /// the agent gets a plausible procedure and every downstream artifact inherits the mistake.
    case wrongSibling
    /// Top-1 was from a different family entirely. Usually visible, usually recovered from.
    case wrongFamily
    /// Nothing survived the policy's filters.
    case empty
}

public struct CaseResult: Identifiable, Hashable, Sendable {
    public let benchmark: BenchmarkCase
    public let candidates: [Candidate]
    public let outcome: Outcome
    /// Expected skill appeared anywhere in the returned list.
    public let recalledAtK: Bool
    /// Top-1 declares `supersededBy` (only possible under a policy that does not exclude them).
    public let topIsStale: Bool
    /// Top-1 has at least one precondition that fails in the case's environment.
    public let topFailsPrecondition: Bool

    public var id: String { benchmark.id }
}

public struct Metrics: Hashable, Sendable {
    public let cases: Int
    public let recallAt1: Double
    public let recallAtK: Double
    public let wrongSiblingRate: Double
    public let wrongFamilyRate: Double
    public let staleTopRate: Double
    public let preconditionMissRate: Double
    public let emptyRate: Double

    /// Of all misses at top-1, the share that were wrong *siblings* rather than wrong families.
    public var siblingShareOfMisses: Double {
        let misses = wrongSiblingRate + wrongFamilyRate + emptyRate
        return misses > 0 ? wrongSiblingRate / misses : 0
    }
}

public struct Evaluator: Sendable {
    public let resolver: Resolver
    public let k: Int

    public init(resolver: Resolver, k: Int = 3) {
        self.resolver = resolver
        self.k = max(k, 1)
    }

    public func run(_ benchmarkCase: BenchmarkCase, policy: ResolutionPolicy) -> CaseResult {
        let candidates = resolver.resolve(benchmarkCase.query, in: benchmarkCase.environment, policy: policy, limit: k)
        let expected = resolver.catalog[benchmarkCase.expectedSkillID]
        let outcome: Outcome
        if let top = candidates.first {
            if top.skill.id == benchmarkCase.expectedSkillID {
                outcome = .hit
            } else if let expected, top.skill.family == expected.family {
                outcome = .wrongSibling
            } else {
                outcome = .wrongFamily
            }
        } else {
            outcome = .empty
        }
        let top = candidates.first?.skill
        return CaseResult(
            benchmark: benchmarkCase,
            candidates: candidates,
            outcome: outcome,
            recalledAtK: candidates.contains { $0.skill.id == benchmarkCase.expectedSkillID },
            topIsStale: top?.isSuperseded ?? false,
            topFailsPrecondition: top.map { s in
                !s.preconditions.allSatisfy { $0.isSatisfied(in: benchmarkCase.environment) }
            } ?? false
        )
    }

    public func evaluate(_ cases: [BenchmarkCase], policy: ResolutionPolicy) -> (Metrics, [CaseResult]) {
        let results = cases.map { run($0, policy: policy) }
        let n = Double(max(results.count, 1))
        func rate(_ p: (CaseResult) -> Bool) -> Double {
            Double(results.filter(p).count) / n
        }
        let metrics = Metrics(
            cases: results.count,
            recallAt1: rate { $0.outcome == .hit },
            recallAtK: rate { $0.recalledAtK },
            wrongSiblingRate: rate { $0.outcome == .wrongSibling },
            wrongFamilyRate: rate { $0.outcome == .wrongFamily },
            staleTopRate: rate { $0.topIsStale },
            preconditionMissRate: rate { $0.topFailsPrecondition },
            emptyRate: rate { $0.outcome == .empty }
        )
        return (metrics, results)
    }
}
