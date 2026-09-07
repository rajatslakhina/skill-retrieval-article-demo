import Foundation

/// Static findings about a skills library, independent of any query. These are the things a
/// retrieval system's index maintainer would check; a documentation folder never does.
public enum LintFinding: Hashable, Sendable, Identifiable, CustomStringConvertible {
    /// Two siblings whose keyword sets overlap above the threshold. A resolver cannot tell them apart.
    case nearDuplicateSiblings(a: String, b: String, jaccard: Double)
    /// Skill is superseded but still in the index, so it still competes for the top slot.
    case supersededStillIndexed(id: String, by: String)
    /// Skill's `supersededBy` points at an id that is not in the catalog.
    case danglingSupersession(id: String, by: String)
    /// Skill has not been touched in longer than `maxAge`.
    case stale(id: String, ageDays: Int)
    /// Skill has siblings but declares no machine-checkable precondition to disambiguate itself.
    case undifferentiatedSibling(id: String, family: String)

    public var id: String { description }

    public var description: String {
        switch self {
        case .nearDuplicateSiblings(let a, let b, let j):
            return "near-duplicate siblings \(a) / \(b) (jaccard \(String(format: "%.2f", j)))"
        case .supersededStillIndexed(let id, let by):
            return "\(id) is superseded by \(by) but still indexed"
        case .danglingSupersession(let id, let by):
            return "\(id) claims supersession by missing skill \(by)"
        case .stale(let id, let days):
            return "\(id) last updated \(days) days ago"
        case .undifferentiatedSibling(let id, let family):
            return "\(id) has siblings in '\(family)' but no checkable precondition"
        }
    }
}

public struct SkillLinter: Sendable {
    public var duplicateThreshold: Double
    public var maxAgeDays: Int

    public init(duplicateThreshold: Double = 0.6, maxAgeDays: Int = 180) {
        self.duplicateThreshold = duplicateThreshold
        self.maxAgeDays = maxAgeDays
    }

    public static func jaccard(_ a: [String], _ b: [String]) -> Double {
        let sa = Set(a.map { $0.lowercased() }), sb = Set(b.map { $0.lowercased() })
        let union = sa.union(sb)
        guard !union.isEmpty else { return 0 }
        return Double(sa.intersection(sb).count) / Double(union.count)
    }

    public func lint(_ catalog: SkillCatalog, now: Date) -> [LintFinding] {
        var findings: [LintFinding] = []
        let skills = catalog.skills
        for skill in skills {
            if let by = skill.supersededBy {
                if catalog[by] == nil {
                    findings.append(.danglingSupersession(id: skill.id, by: by))
                } else {
                    findings.append(.supersededStillIndexed(id: skill.id, by: by))
                }
            }
            let age = Int(now.timeIntervalSince(skill.updatedAt) / 86_400)
            if age > maxAgeDays {
                findings.append(.stale(id: skill.id, ageDays: age))
            }
            if !catalog.siblings(of: skill).isEmpty, skill.preconditions.isEmpty, !skill.isSuperseded {
                findings.append(.undifferentiatedSibling(id: skill.id, family: skill.family))
            }
        }
        for i in skills.indices {
            for j in skills.indices where j > i {
                let a = skills[i], b = skills[j]
                guard a.family == b.family else { continue }
                let jac = SkillLinter.jaccard(a.keywords, b.keywords)
                if jac >= duplicateThreshold {
                    findings.append(.nearDuplicateSiblings(a: a.id, b: b.id, jaccard: jac))
                }
            }
        }
        return findings
    }
}
