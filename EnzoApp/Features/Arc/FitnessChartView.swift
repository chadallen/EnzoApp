import SwiftUI
import Charts

enum ChartTimeframe: String, CaseIterable {
    case ytd       = "YTD"
    case oneYear   = "1Y"
    case fiveYears = "5Y"
    case allTime   = "All"
}

struct FitnessChartView: View {
    let snapshots: [FitnessSnapshot]
    let goalValue: Double

    @State private var selectedTimeframe: ChartTimeframe = .oneYear
    @State private var selectedSnapshot: FitnessSnapshot? = nil
    @State private var showingDetail = false
    @State private var appeared = false

    private var filteredSnapshots: [FitnessSnapshot] {
        let now = Date()
        let calendar = Calendar.current
        switch selectedTimeframe {
        case .allTime:
            return snapshots
        case .fiveYears:
            let cutoff = calendar.date(byAdding: .year, value: -5, to: now)!
            return snapshots.filter { $0.monthDate >= cutoff }
        case .oneYear:
            let cutoff = calendar.date(byAdding: .year, value: -1, to: now)!
            return snapshots.filter { $0.monthDate >= cutoff }
        case .ytd:
            var comps = calendar.dateComponents([.year], from: now)
            comps.month = 1; comps.day = 1
            let cutoff = calendar.date(from: comps)!
            return snapshots.filter { $0.monthDate >= cutoff }
        }
    }

    private var peakValue: Double {
        filteredSnapshots.max(by: { $0.value < $1.value })?.value ?? 1.0
    }

    private var yDomain: ClosedRange<Double> {
        guard !filteredSnapshots.isEmpty else { return 0...1 }
        let values = filteredSnapshots.map(\.value)
        let minVal = values.min()!
        let maxVal = values.max()!
        let range = max(maxVal - minVal, 0.05)
        let padding = range * 0.3
        let lower = max(0.0, minVal - padding)
        let upper = min(1.05, maxVal + padding)
        return lower...upper
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fitness history")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.enzoSecondary)
                .textCase(.uppercase)
                .tracking(1)

            timeframePicker

            chart
                .frame(height: 160)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
                .onAppear {
                    withAnimation(.easeOut(duration: 0.6)) { appeared = true }
                }
                .sheet(isPresented: $showingDetail) {
                    if let snap = selectedSnapshot {
                        MonthDetailSheet(snapshot: snap)
                    }
                }
        }
        .padding()
        .background(Color.enzoCard, in: RoundedRectangle(cornerRadius: 16))
    }

    private var timeframePicker: some View {
        HStack(spacing: 0) {
            ForEach(ChartTimeframe.allCases, id: \.self) { tf in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTimeframe = tf
                        selectedSnapshot = nil
                    }
                } label: {
                    Text(tf.rawValue)
                        .font(.system(.caption, design: .rounded,
                                      weight: selectedTimeframe == tf ? .semibold : .regular))
                        .foregroundStyle(selectedTimeframe == tf ? Color.enzoPrimary : Color.enzoSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            selectedTimeframe == tf ? Color.enzoBg : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.enzoSecondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }

    private var chart: some View {
        Chart {
            ForEach(filteredSnapshots) { snap in
                AreaMark(
                    x: .value("Month", snap.monthDate),
                    y: .value("Fitness", snap.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.enzoChartPrimary.opacity(0.25), Color.enzoChartPrimary.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
            }

            ForEach(filteredSnapshots) { snap in
                LineMark(
                    x: .value("Month", snap.monthDate),
                    y: .value("Fitness", snap.value)
                )
                .foregroundStyle(Color.enzoChartPrimary)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.catmullRom)
            }

            if let current = filteredSnapshots.last {
                PointMark(
                    x: .value("Month", current.monthDate),
                    y: .value("Fitness", current.value)
                )
                .foregroundStyle(Color.enzoChartPrimary)
                .symbolSize(60)
            }

            RuleMark(y: .value("Peak", peakValue))
                .foregroundStyle(Color.enzoSecondary.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .annotation(position: .top, alignment: .trailing) {
                    Text("Your peak")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.enzoSecondary)
                        .padding(.trailing, 4)
                }

            RuleMark(y: .value("Goal target", goalValue))
                .foregroundStyle(Color.enzoGoal.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .annotation(position: .top, alignment: .leading) {
                    Text("Goal target")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.enzoGoal)
                        .padding(.leading, 4)
                }

            if let sel = selectedSnapshot {
                RuleMark(x: .value("Selected", sel.monthDate))
                    .foregroundStyle(Color.enzoPrimary.opacity(0.15))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
        }
        .chartYScale(domain: yDomain)
        .chartXAxis { xAxisMarks }
        .chartYAxis(.hidden)
        .chartBackground { _ in Color.enzoCard }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        guard let plotFrame = proxy.plotFrame else { return }
                        let frame = geo[plotFrame]
                        guard frame.contains(location) else { return }
                        let plotX = location.x - frame.origin.x
                        if let date: Date = proxy.value(atX: plotX) {
                            let closest = filteredSnapshots.min {
                                abs($0.monthDate.timeIntervalSince(date)) <
                                abs($1.monthDate.timeIntervalSince(date))
                            }
                            selectedSnapshot = closest
                            showingDetail = closest != nil
                        }
                    }
            }
        }
    }
    @AxisContentBuilder
    private var xAxisMarks: some AxisContent {
        if selectedTimeframe == .ytd {
            AxisMarks(values: .stride(by: .month, count: 1)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.enzoSecondary)
            }
        } else if selectedTimeframe == .oneYear {
            AxisMarks(values: .stride(by: .month, count: 1)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.enzoSecondary)
            }
        } else {
            AxisMarks(values: .stride(by: .year, count: 1)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(abbreviatedYear(from: date))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Color.enzoSecondary)
                    }
                }
            }
        }
    }

    private func abbreviatedYear(from date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "''yy"
        return f.string(from: date)
    }
}

#Preview {
    FitnessChartView(
        snapshots: FitnessSnapshot.previewSnapshots,
        goalValue: 0.70
    )
    .padding()
    .background(Color.enzoBg)
}
