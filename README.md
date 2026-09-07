# skill-retrieval-article-demo

**A skills library is a retrieval system, not a folder of documentation.** This package treats it as one: an index of `Skill` entries with capability families, versions, dates and *machine-checkable* preconditions; a deliberately ordinary TF-IDF resolver; a 32-case benchmark; and an evaluator that grades the thing nobody measures — the **wrong-sibling rate**, where the resolver lands in the right capability family and hands the agent the wrong procedure inside it.

Article: (added after publish)

## What it shows

Same 29-skill library, same 32 queries, same resolver. The only thing that changes is the policy around it.

| Policy | Recall@1 | Recall@3 | Wrong sibling | Wrong family | Stale top-1 | Precondition miss | Empty |
|---|---|---|---|---|---|---|---|
| Naive (rank by text) | 68.8% | 87.5% | **28.1%** | 3.1% | 3.1% | 12.5% | 0% |
| Exclude superseded only | 71.9% | 87.5% | 25.0% | 3.1% | 0% | 12.5% | 0% |
| Enforce preconditions only | 71.9% | 93.8% | 15.6% | 12.5% | 3.1% | 0% | 0% |
| Rerank siblings only | 81.3% | 90.6% | 15.6% | 3.1% | 0% | 9.4% | 0% |
| All four rules | **81.3%** | **93.8%** | **6.3%** | 9.4% | **0%** | **0%** | 3.1% |

Nine of the naive resolver's ten misses are wrong *siblings* — plausible, in-family, un-runnable in the caller's environment. With all four hygiene rules on, two remain, and the linter names the reason for one of them before the benchmark does (`ui-swiftui-view has siblings in 'ui' but no checkable precondition`). Every number above is pinned by a test, so a fixture edit that changes them fails `swift test`.

## The pieces

```swift
// A skill is an index entry, not a markdown file.
Skill(id: "release-testflight-v2", family: "release",
      title: "Upload a build to TestFlight (App Store Connect API)",
      summary: "…", keywords: ["testflight", "upload", "ipa", "archive", "api", "key"],
      version: 2, updatedAt: day(30),
      preconditions: [.fileExists("ExportOptions.plist")])

// The four hygiene rules, each measured on its own and together.
public static let hygienic = ResolutionPolicy(
    excludeSuperseded: true,      // a superseded skill is still text; it still matches
    enforcePreconditions: true,   // drop skills that cannot run in this environment
    rerankSiblings: true,         // lexical noise between siblings is not evidence; fit is
    minimumScore: 0.1)            // an empty answer is a question; a low-score wrong one is a confident mistake
```

`Evaluator` classifies every case as `hit`, `wrongSibling`, `wrongFamily` or `empty` and reports recall, wrong-sibling rate, stale-top rate and precondition-miss rate. `SkillLinter` finds near-duplicate siblings, superseded-but-indexed entries, dangling supersession, stale entries and siblings with nothing checkable to tell them apart.

## Run it

```bash
git clone https://github.com/rajatslakhina/skill-retrieval-article-demo.git
cd skill-retrieval-article-demo
swift test            # 18 tests
open Demo.xcodeproj   # pick the Demo scheme + any iPhone Simulator, Build & Run
```

The app has two tabs: **Benchmark** (four toggles, the metrics grid, all 32 cases with their top-3 and the expected skill highlighted) and **Lint** (the linter's findings on the fixture library).

## Verification status

- `swift build` and `swift test` (Swift 6.0.3, Linux aarch64): 18/18 passing, 0 warnings.
- **Simulator run: not completed for this release.** The automated run that produced this repo found Xcode already open on an unrelated production project and, by rule, did not touch it. `Demo.xcodeproj` was hand-authored and checked for brace/paren balance and dangling object references, and the SwiftUI view uses only iOS 17 APIs (`Grid`, `NavigationStack`, `TabView`) — but no screenshot exists yet, and `Demo/Screenshots/` says so. If you run it, a PR with a screenshot is welcome.

## Credits

The measurement framing follows three papers: SkillJuror ([arXiv 2606.11543](https://arxiv.org/abs/2606.11543)), SkillResolve-Bench ([arXiv 2606.10388](https://arxiv.org/abs/2606.10388)) and SkillTV-Bench ([arXiv 2608.05573](https://arxiv.org/abs/2608.05573)). The fixture, resolver and benchmark here are original and much smaller than any of them.

MIT licensed.
