import Charts
import SwiftUI

extension HealthSeverity {
    var tint: Color {
        switch self {
        case .excellent: .green
        case .normal: .blue
        case .elevated: .orange
        case .high: .red
        case .critical: .red
        case .unavailable: .secondary
        }
    }
}

struct MacHealthOverviewCard: View {
    let snapshot: MacHealthSnapshot
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Label(L10n.text("health.title"), systemImage: "gauge.with.dots.needle.67percent")
                        .font(.title2.weight(.semibold))
                    Spacer()
                    Text("\(snapshot.overallScore) / 100")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(snapshot.overallSeverity.tint)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(snapshot.overallTitle).font(.headline)
                    Text(snapshot.summary).font(.callout).foregroundStyle(.secondary)
                    if let root = snapshot.primaryRootCause {
                        Text(L10n.format("health.primaryCause.inline", root.name)).font(.callout.weight(.medium))
                    }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), spacing: 10)], alignment: .leading, spacing: 8) {
                    ForEach(snapshot.categories) { category in
                        HStack(spacing: 6) {
                            Image(systemName: category.category.symbol).foregroundStyle(category.severity.tint)
                            Text(category.category.title)
                            Spacer(minLength: 4)
                            Text(category.severity.title).foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }
                }
                HStack {
                    Text(snapshot.baselineState.title).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Label(L10n.text("health.openDetails"), systemImage: "chevron.right").font(.caption.weight(.medium))
                }
            }
            .padding(20)
            .background(.background, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(snapshot.overallSeverity.tint.opacity(0.28), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.format("health.accessibility.summary", snapshot.overallScore, snapshot.overallTitle))
        .accessibilityHint(L10n.text("health.openDetails"))
        .accessibilityIdentifier("mac-health-card")
    }
}

struct MacHealthDetailView: View {
    let snapshot: MacHealthSnapshot
    let history: [HealthHistoryPoint]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                HealthHero(snapshot: snapshot)
                if snapshot.activeIssues.isEmpty {
                    ContentUnavailableView(L10n.text("health.noIssues"), systemImage: "checkmark.circle", description: Text(snapshot.summary))
                        .frame(minHeight: 150)
                } else {
                    HealthIssuesSection(issues: snapshot.activeIssues)
                }
                HealthCategoriesSection(categories: snapshot.categories)
                HealthExplanationSection(snapshot: snapshot)
                HealthScoreChart(points: history)
                Text(L10n.text("health.currentConditionDisclaimer"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(28)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("mac-health-detail")
    }
}

private struct HealthHero: View {
    let snapshot: MacHealthSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 22) {
            VStack(alignment: .leading, spacing: 7) {
                Text(L10n.text("health.title")).font(.largeTitle.weight(.semibold))
                Text(snapshot.overallTitle).font(.title3.weight(.medium)).foregroundStyle(snapshot.overallSeverity.tint)
                Text(snapshot.summary).foregroundStyle(.secondary)
                Text(snapshot.baselineState.title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(snapshot.overallScore)")
                .font(.system(size: 58, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(snapshot.overallSeverity.tint)
                .accessibilityLabel(L10n.format("health.accessibility.score", snapshot.overallScore))
        }
    }
}

private struct HealthIssuesSection: View {
    let issues: [HealthIssue]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("health.currentIssues")).font(.title2.weight(.semibold))
            ForEach(issues) { issue in HealthIssueCard(issue: issue) }
        }
    }
}

private struct HealthIssueCard: View {
    let issue: HealthIssue

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label(issue.title, systemImage: issue.category.symbol).font(.headline)
                Spacer()
                Text(issue.severity.title).font(.caption.weight(.semibold)).foregroundStyle(issue.severity.tint)
            }
            Text(issue.summary).foregroundStyle(.secondary)
            if let root = issue.rootCause {
                VStack(alignment: .leading, spacing: 4) {
                    Text(root.role).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Text(root.name).fontWeight(.semibold)
                        Spacer()
                        Text(root.confidence.title).font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(root.evidence) { item in HealthEvidenceRow(evidence: item) }
                }
            }
            if !issue.evidence.isEmpty {
                Divider()
                ForEach(issue.evidence) { item in HealthEvidenceRow(evidence: item) }
            }
            if let recommendation = issue.recommendation {
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(recommendation.title).font(.caption.weight(.semibold))
                        Text(recommendation.detail).font(.callout)
                    }
                } icon: {
                    Image(systemName: "lightbulb")
                }
                .foregroundStyle(.primary)
            }
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(issue.severity.tint.opacity(0.24)))
        .accessibilityElement(children: .contain)
    }
}

private struct HealthEvidenceRow: View {
    let evidence: HealthEvidence

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(evidence.label).foregroundStyle(.secondary)
                if let detail = evidence.detail { Text(detail).font(.caption2).foregroundStyle(.tertiary) }
            }
            Spacer()
            Text(evidence.value).monospacedDigit().multilineTextAlignment(.trailing)
        }
        .font(.caption)
    }
}

private struct HealthCategoriesSection: View {
    let categories: [HealthCategorySnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("health.categories")).font(.title2.weight(.semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
                ForEach(categories) { category in HealthCategoryCard(snapshot: category) }
            }
        }
    }
}

private struct HealthCategoryCard: View {
    let snapshot: HealthCategorySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(snapshot.category.title, systemImage: snapshot.category.symbol).font(.headline)
                Spacer()
                Text("\(snapshot.score)").font(.title2.weight(.semibold)).monospacedDigit()
            }
            Text(snapshot.status).font(.callout).foregroundStyle(snapshot.severity.tint)
            Label(snapshot.trend.title, systemImage: trendSymbol).font(.caption).foregroundStyle(.secondary)
            ForEach(snapshot.evidence.prefix(3)) { evidence in HealthEvidenceRow(evidence: evidence) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 155, alignment: .topLeading)
        .background(.background, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(.primary.opacity(0.06)))
        .accessibilityElement(children: .contain)
    }

    private var trendSymbol: String {
        switch snapshot.trend {
        case .rising: "arrow.up.right"
        case .falling: "arrow.down.right"
        case .stable: "arrow.right"
        case .unavailable: "minus"
        }
    }
}

private struct HealthExplanationSection: View {
    let snapshot: MacHealthSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("health.whyScore")).font(.title2.weight(.semibold))
            if snapshot.activeIssues.isEmpty {
                Text(L10n.text("health.noDeductions")).foregroundStyle(.secondary)
            } else {
                ForEach(snapshot.activeIssues) { issue in
                    HStack {
                        Text(issue.title)
                        Spacer()
                        Text("−\(issue.penalty)").monospacedDigit().foregroundStyle(issue.severity.tint)
                    }
                }
                Text(L10n.text("health.diminishingWeights")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct HealthScoreChart: View {
    let points: [HealthHistoryPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("health.history")).font(.title2.weight(.semibold))
            if points.isEmpty {
                ContentUnavailableView(L10n.text("No readings yet"), systemImage: "chart.xyaxis.line")
                    .frame(height: 160)
            } else {
                Chart(points) { point in
                    LineMark(
                        x: .value(L10n.text("Time"), point.date),
                        y: .value(L10n.text("health.score"), point.overallScore)
                    )
                    .foregroundStyle(Color.accentColor)
                    .interpolationMethod(.monotone)
                }
                .chartYScale(domain: 0...100)
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) { AxisValueLabel(format: .dateTime.hour().minute()); AxisGridLine() } }
                .chartYAxis { AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) }
                .frame(height: 180)
                .accessibilityLabel(L10n.format("health.accessibility.history", points.count))
            }
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
    }
}
