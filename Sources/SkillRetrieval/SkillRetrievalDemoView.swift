#if canImport(SwiftUI)
import SwiftUI

/// The demo's root view: flip the four hygiene rules on and off and watch the benchmark
/// outcomes reclassify. The second tab is the linter's static view of the same library.
public struct SkillRetrievalDemoView: View {
    public init() {}

    public var body: some View {
        TabView {
            BenchmarkScreen()
                .tabItem { Label("Benchmark", systemImage: "chart.bar.doc.horizontal") }
            LintScreen()
                .tabItem { Label("Lint", systemImage: "exclamationmark.triangle") }
        }
    }
}

struct BenchmarkScreen: View {
    @State private var excludeSuperseded = false
    @State private var enforcePreconditions = false
    @State private var rerankSiblings = false
    @State private var minimumScore = false

    private let evaluator = Evaluator(resolver: Resolver(catalog: Fixture.catalog), k: 3)

    private var policy: ResolutionPolicy {
        ResolutionPolicy(
            excludeSuperseded: excludeSuperseded,
            enforcePreconditions: enforcePreconditions,
            rerankSiblings: rerankSiblings,
            minimumScore: minimumScore ? 0.1 : 0)
    }

    var body: some View {
        let (metrics, results) = evaluator.evaluate(Fixture.benchmark, policy: policy)
        NavigationStack {
            List {
                Section("Hygiene rules") {
                    Toggle("Exclude superseded", isOn: $excludeSuperseded)
                    Toggle("Enforce preconditions", isOn: $enforcePreconditions)
                    Toggle("Rerank siblings by fit", isOn: $rerankSiblings)
                    Toggle("Refuse below score 0.10", isOn: $minimumScore)
                    HStack {
                        Button("Naive") { set(.naive) }
                        Spacer()
                        Button("All four") { set(.hygienic) }
                    }
                    .buttonStyle(.bordered)
                }
                Section("32 cases, top-3") {
                    MetricsGrid(metrics: metrics)
                }
                Section("Cases") {
                    ForEach(results) { result in
                        CaseRow(result: result)
                    }
                }
            }
            .navigationTitle("Skill retrieval")
        }
    }

    private func set(_ p: ResolutionPolicy) {
        excludeSuperseded = p.excludeSuperseded
        enforcePreconditions = p.enforcePreconditions
        rerankSiblings = p.rerankSiblings
        minimumScore = p.minimumScore > 0
    }
}

struct MetricsGrid: View {
    let metrics: Metrics

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            row("Recall@1", metrics.recallAt1, good: true)
            row("Recall@3", metrics.recallAtK, good: true)
            row("Wrong sibling", metrics.wrongSiblingRate, good: false)
            row("Wrong family", metrics.wrongFamilyRate, good: false)
            row("Stale top-1", metrics.staleTopRate, good: false)
            row("Precondition miss", metrics.preconditionMissRate, good: false)
            row("Empty", metrics.emptyRate, good: false)
        }
        .font(.callout.monospacedDigit())
    }

    private func row(_ label: String, _ value: Double, good: Bool) -> some View {
        GridRow {
            Text(label)
            Text(String(format: "%5.1f%%", value * 100))
                .foregroundStyle(good ? Color.primary : (value == 0 ? Color.secondary : Color.red))
                .gridColumnAlignment(.trailing)
            ProgressView(value: value)
                .tint(good ? .green : .red)
        }
    }
}

struct CaseRow: View {
    let result: CaseResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(result.benchmark.id).font(.caption.monospaced()).foregroundStyle(.secondary)
                OutcomeChip(outcome: result.outcome)
                Spacer()
                Text(environmentSummary).font(.caption2).foregroundStyle(.secondary)
            }
            Text("“\(result.benchmark.query)”").font(.subheadline)
            ForEach(Array(result.candidates.enumerated()), id: \.element.id) { index, candidate in
                HStack(spacing: 6) {
                    Text("\(index + 1).").font(.caption.monospaced())
                    Text(candidate.skill.id).font(.caption.monospaced())
                        .foregroundStyle(candidate.skill.id == result.benchmark.expectedSkillID ? Color.green : Color.primary)
                    if candidate.skill.isSuperseded {
                        Text("superseded").font(.caption2).foregroundStyle(.orange)
                    }
                    Spacer()
                    Text(String(format: "%.2f", candidate.score)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            if result.candidates.isEmpty {
                Text("no candidate above the score floor — ask the human").font(.caption).foregroundStyle(.secondary)
            }
            if result.outcome != .hit {
                Text("expected \(result.benchmark.expectedSkillID)").font(.caption2).foregroundStyle(.green)
            }
        }
        .padding(.vertical, 2)
    }

    private var environmentSummary: String {
        let env = result.benchmark.environment
        let tools = env.toolVersions.keys.sorted().map { "\($0) \(env.toolVersions[$0] ?? 0)" }
        return (env.files.sorted() + tools).joined(separator: " · ")
    }
}

struct OutcomeChip: View {
    let outcome: Outcome

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }

    private var label: String {
        switch outcome {
        case .hit: return "HIT"
        case .wrongSibling: return "WRONG SIBLING"
        case .wrongFamily: return "WRONG FAMILY"
        case .empty: return "EMPTY"
        }
    }

    private var color: Color {
        switch outcome {
        case .hit: return .green
        case .wrongSibling: return .red
        case .wrongFamily: return .orange
        case .empty: return .gray
        }
    }
}

struct LintScreen: View {
    private let findings = SkillLinter().lint(Fixture.catalog, now: Fixture.now)

    var body: some View {
        NavigationStack {
            List {
                Section("\(findings.count) findings across \(Fixture.catalog.count) skills") {
                    ForEach(findings) { finding in
                        Text(finding.description).font(.caption.monospaced())
                    }
                }
            }
            .navigationTitle("Library lint")
        }
    }
}

#Preview {
    SkillRetrievalDemoView()
}
#endif
