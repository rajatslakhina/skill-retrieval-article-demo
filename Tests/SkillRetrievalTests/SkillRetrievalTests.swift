import XCTest
@testable import SkillRetrieval

private let resolver = Resolver(catalog: Fixture.catalog)
private let evaluator = Evaluator(resolver: resolver, k: 3)

final class ModelTests: XCTestCase {
    func testTokenizerSplitsOnNonAlphanumericsAndDropsSingleCharacters() {
        XCTAssertEqual(Resolver.tokenize("Swift 6.4: @Test/#expect, a b"), ["swift", "test", "expect"])
    }

    func testCatalogIsIDAddressableAndSortedWithSiblingsByFamily() {
        let c = Fixture.catalog
        XCTAssertEqual(c.count, 29)
        XCTAssertEqual(c.skills.map(\.id), c.skills.map(\.id).sorted())
        XCTAssertNotNil(c["release-testflight-v2"])
        XCTAssertNil(c["release-testflight-v3"])
        let sibs = c.siblings(of: c["persist-swiftdata"]!).map(\.id)
        XCTAssertEqual(sibs, ["persist-coredata", "persist-keychain"])
        XCTAssertEqual(c.families.count, 8)
    }

    func testPreconditionsAreCheckedAgainstTheEnvironment() {
        let env = Environment(files: ["Package.swift"], toolVersions: ["swift": 6])
        XCTAssertTrue(Precondition.fileExists("Package.swift").isSatisfied(in: env))
        XCTAssertFalse(Precondition.fileExists("Fastfile").isSatisfied(in: env))
        XCTAssertTrue(Precondition.toolAvailable("swift").isSatisfied(in: env))
        XCTAssertFalse(Precondition.toolAvailable("ios").isSatisfied(in: env))
        XCTAssertTrue(Precondition.minimumToolVersion(tool: "swift", version: 6).isSatisfied(in: env))
        XCTAssertFalse(Precondition.minimumToolVersion(tool: "swift", version: 7).isSatisfied(in: env))
        XCTAssertFalse(Precondition.minimumToolVersion(tool: "ios", version: 1).isSatisfied(in: env), "missing tool never satisfies a version floor")
    }

    func testBenchmarkIsWellFormed() {
        let ids = Fixture.benchmark.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "case ids are unique")
        XCTAssertEqual(ids.count, 32)
        for c in Fixture.benchmark {
            let expected = Fixture.catalog[c.expectedSkillID]
            XCTAssertNotNil(expected, "\(c.id) expects a skill that exists")
            XCTAssertFalse(expected?.isSuperseded ?? true, "\(c.id) must not expect a superseded skill")
            XCTAssertTrue(expected?.preconditions.allSatisfy { $0.isSatisfied(in: c.environment) } ?? false,
                          "\(c.id)'s expected skill must be runnable in its own environment")
        }
    }
}

final class ResolverTests: XCTestCase {
    func testNaiveTieBreakIsDirectoryOrderSoTheStaleSiblingWins() {
        // Same query, same environment. The v1 skill has more matching text (it is older and
        // accumulated more keywords), and on a tie directory order favours "v1" < "v2".
        let env = Environment(files: ["App.xcodeproj", "ExportOptions.plist"], toolVersions: ["ios": 26])
        let naive = resolver.resolve("archive and export an ipa for beta testers", in: env, policy: .naive)
        XCTAssertEqual(naive.first?.skill.id, "release-testflight-v1")
        XCTAssertTrue(naive.first?.skill.isSuperseded ?? false)
        let hygienic = resolver.resolve("archive and export an ipa for beta testers", in: env, policy: .hygienic)
        XCTAssertEqual(hygienic.first?.skill.id, "release-testflight-v2")
    }

    func testExcludeSupersededRemovesEveryStaleSkillFromEveryResult() {
        let policy = ResolutionPolicy(excludeSuperseded: true, enforcePreconditions: false, rerankSiblings: false)
        for c in Fixture.benchmark {
            let r = resolver.resolve(c.query, in: c.environment, policy: policy, limit: 28)
            XCTAssertFalse(r.contains { $0.skill.isSuperseded }, c.id)
        }
    }

    func testPreconditionEnforcementNeverHandsOutLiquidGlassOnIOS17() {
        let env = Environment(files: ["App.xcodeproj"], toolVersions: ["ios": 17])
        let naive = resolver.resolve("apply glass material to the custom tab bar chrome", in: env, policy: .naive)
        XCTAssertEqual(naive.first?.skill.id, "ui-liquid-glass", "the naive resolver confidently returns a skill that cannot run here")
        let policy = ResolutionPolicy(excludeSuperseded: false, enforcePreconditions: true, rerankSiblings: false)
        let strict = resolver.resolve("apply glass material to the custom tab bar chrome", in: env, policy: policy, limit: 28)
        XCTAssertFalse(strict.contains { $0.skill.id == "ui-liquid-glass" })
    }

    func testMinimumScoreReturnsEmptyInsteadOfGarbage() {
        let env = Environment(files: ["App.xcodeproj"], toolVersions: ["ios": 17])
        let r = resolver.resolve("apply glass material to the custom tab bar chrome", in: env, policy: .hygienic)
        XCTAssertTrue(r.isEmpty, "with glass filtered out, the best remaining score is below the floor")
        XCTAssertTrue(resolver.resolve("zzz qqq", policy: .hygienic).isEmpty)
        XCTAssertFalse(resolver.resolve("zzz qqq", policy: .naive).isEmpty, "naive always answers")
    }

    func testSiblingRerankPicksTheSiblingThatFitsTheEnvironment() {
        let query = "save the user's drafts to a local database"
        let modern = Environment(files: ["App.xcodeproj"], toolVersions: ["ios": 26])
        let legacy = Environment(files: ["App.xcodeproj"], toolVersions: ["ios": 16])
        XCTAssertEqual(resolver.resolve(query, in: modern, policy: .naive).first?.skill.id, "persist-coredata")
        XCTAssertEqual(resolver.resolve(query, in: modern, policy: .hygienic).first?.skill.id, "persist-swiftdata")
        XCTAssertEqual(resolver.resolve(query, in: legacy, policy: .hygienic).first?.skill.id, "persist-coredata")
    }

    func testRerankOnlyReordersWithinTheTopFamily() {
        // The band is family-scoped: a well-fitting skill from another family must not jump the queue.
        let env = Environment(files: ["Package.swift"], toolVersions: ["swift": 6])
        let policy = ResolutionPolicy(excludeSuperseded: false, enforcePreconditions: false, rerankSiblings: true)
        let r = resolver.resolve("symbolicate this crash report with the dsym", in: env, policy: policy)
        XCTAssertEqual(r.first?.skill.family, "debug")
    }

    func testLimitIsClampedAndOrderingIsDeterministic() {
        XCTAssertTrue(resolver.resolve("build", limit: 0).isEmpty)
        XCTAssertTrue(resolver.resolve("build", limit: -3).isEmpty)
        let a = resolver.resolve("build the app", limit: 10).map(\.id)
        let b = resolver.resolve("build the app", limit: 10).map(\.id)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.count, 10)
    }
}

final class EvaluatorTests: XCTestCase {
    private let tiny = SkillCatalog([
        Skill(id: "a-1", family: "a", title: "alpha one", summary: "", keywords: ["alpha", "one"], updatedAt: Fixture.now),
        Skill(id: "a-2", family: "a", title: "alpha two", summary: "", keywords: ["alpha", "two"], updatedAt: Fixture.now),
        Skill(id: "b-1", family: "b", title: "beta", summary: "", keywords: ["beta"], updatedAt: Fixture.now),
    ])

    func testOutcomeClassification() {
        let ev = Evaluator(resolver: Resolver(catalog: tiny), k: 2)
        let env = Environment()
        XCTAssertEqual(ev.run(BenchmarkCase(id: "1", query: "alpha one", environment: env, expectedSkillID: "a-1"), policy: .naive).outcome, .hit)
        XCTAssertEqual(ev.run(BenchmarkCase(id: "2", query: "alpha one", environment: env, expectedSkillID: "a-2"), policy: .naive).outcome, .wrongSibling)
        XCTAssertEqual(ev.run(BenchmarkCase(id: "3", query: "alpha one", environment: env, expectedSkillID: "b-1"), policy: .naive).outcome, .wrongFamily)
        let strict = ResolutionPolicy(excludeSuperseded: false, enforcePreconditions: false, rerankSiblings: false, minimumScore: 0.99)
        XCTAssertEqual(ev.run(BenchmarkCase(id: "4", query: "gamma", environment: env, expectedSkillID: "b-1"), policy: strict).outcome, .empty)
        XCTAssertTrue(ev.run(BenchmarkCase(id: "5", query: "alpha one", environment: env, expectedSkillID: "a-2"), policy: .naive).recalledAtK)
    }

    func testKIsAtLeastOneAndEmptyBenchmarkDoesNotDivideByZero() {
        let ev = Evaluator(resolver: Resolver(catalog: tiny), k: 0)
        XCTAssertEqual(ev.k, 1)
        let (m, r) = ev.evaluate([], policy: .naive)
        XCTAssertTrue(r.isEmpty)
        XCTAssertEqual(m.cases, 0)
        XCTAssertEqual(m.recallAt1, 0)
        XCTAssertEqual(m.siblingShareOfMisses, 0)
    }

    // The next two tests pin the numbers the article quotes. If the fixture or the policy
    // changes, these fail before a stale claim can be published.
    func testNaiveResolverMissesAreOverwhelminglyWrongSiblings() {
        let (m, _) = evaluator.evaluate(Fixture.benchmark, policy: .naive)
        XCTAssertEqual(m.cases, 32)
        XCTAssertEqual(m.recallAt1, 22.0 / 32, accuracy: 1e-9)
        XCTAssertEqual(m.recallAtK, 28.0 / 32, accuracy: 1e-9)
        XCTAssertEqual(m.wrongSiblingRate, 9.0 / 32, accuracy: 1e-9)
        XCTAssertEqual(m.wrongFamilyRate, 1.0 / 32, accuracy: 1e-9)
        XCTAssertEqual(m.staleTopRate, 1.0 / 32, accuracy: 1e-9)
        XCTAssertEqual(m.preconditionMissRate, 4.0 / 32, accuracy: 1e-9)
        XCTAssertEqual(m.siblingShareOfMisses, 0.9, accuracy: 1e-9)
    }

    func testHygienicResolverTradesSilentMissesForLoudOnes() {
        let (m, results) = evaluator.evaluate(Fixture.benchmark, policy: .hygienic)
        XCTAssertEqual(m.recallAt1, 26.0 / 32, accuracy: 1e-9)
        XCTAssertEqual(m.recallAtK, 30.0 / 32, accuracy: 1e-9)
        XCTAssertEqual(m.wrongSiblingRate, 2.0 / 32, accuracy: 1e-9)
        XCTAssertEqual(m.wrongFamilyRate, 3.0 / 32, accuracy: 1e-9)
        XCTAssertEqual(m.emptyRate, 1.0 / 32, accuracy: 1e-9)
        XCTAssertEqual(m.staleTopRate, 0)
        XCTAssertEqual(m.preconditionMissRate, 0)
        // The two remaining wrong siblings are the ones the linter and the lexical index explain:
        // c15 has siblings with no checkable precondition; c20's expected skill never entered the top 3.
        let stillWrong = results.filter { $0.outcome == .wrongSibling }.map(\.id)
        XCTAssertEqual(stillWrong, ["c15", "c20"])
    }

    func testEachHygieneRuleAloneIsWorseThanAllFour() {
        let alone: [ResolutionPolicy] = [
            ResolutionPolicy(excludeSuperseded: true, enforcePreconditions: false, rerankSiblings: false),
            ResolutionPolicy(excludeSuperseded: false, enforcePreconditions: true, rerankSiblings: false),
            ResolutionPolicy(excludeSuperseded: false, enforcePreconditions: false, rerankSiblings: true),
        ]
        let (all, _) = evaluator.evaluate(Fixture.benchmark, policy: .hygienic)
        for p in alone {
            let (m, _) = evaluator.evaluate(Fixture.benchmark, policy: p)
            XCTAssertGreaterThan(m.wrongSiblingRate, all.wrongSiblingRate)
            XCTAssertLessThanOrEqual(m.recallAt1, all.recallAt1)
        }
    }
}

final class LintTests: XCTestCase {
    func testFixtureLintFindsTheProblemsThatWerePlanted() {
        let findings = SkillLinter().lint(Fixture.catalog, now: Fixture.now)
        let superseded = findings.filter { if case .supersededStillIndexed = $0 { return true } else { return false } }
        XCTAssertEqual(superseded.count, 2)
        let dangling = findings.filter { if case .danglingSupersession = $0 { return true } else { return false } }
        XCTAssertEqual(dangling.map(\.description), ["debug-oslog-v1 claims supersession by missing skill debug-logger-v2"])
        let stale = findings.filter { if case .stale = $0 { return true } else { return false } }
        XCTAssertEqual(stale.count, 7)
        let undiff = findings.filter { if case .undifferentiatedSibling(let id, _) = $0 { return id == "ui-swiftui-view" } else { return false } }
        XCTAssertEqual(undiff.count, 1, "the linter names the sibling that c15 fails on")
    }

    func testNearDuplicateSiblingsAreReportedOnlyWithinAFamily() {
        let cat = SkillCatalog([
            Skill(id: "x-1", family: "x", title: "", summary: "", keywords: ["a", "b", "c", "d"], updatedAt: Fixture.now),
            Skill(id: "x-2", family: "x", title: "", summary: "", keywords: ["a", "b", "c", "e"], updatedAt: Fixture.now),
            Skill(id: "y-1", family: "y", title: "", summary: "", keywords: ["a", "b", "c", "d"], updatedAt: Fixture.now),
        ])
        let findings = SkillLinter(duplicateThreshold: 0.6).lint(cat, now: Fixture.now)
        let dupes = findings.compactMap { f -> (String, String)? in
            if case .nearDuplicateSiblings(let a, let b, _) = f { return (a, b) } else { return nil }
        }
        XCTAssertEqual(dupes.count, 1)
        XCTAssertEqual(dupes.first?.0, "x-1")
        XCTAssertEqual(dupes.first?.1, "x-2")
        XCTAssertEqual(SkillLinter.jaccard([], []), 0)
        XCTAssertEqual(SkillLinter.jaccard(["A"], ["a"]), 1)
    }
}
