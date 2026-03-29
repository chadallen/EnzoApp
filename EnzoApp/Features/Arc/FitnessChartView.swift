import SwiftUI
import Charts

struct FitnessChartView: View {
    let snapshots: [FitnessSnapshot]
    let goalValue: Double   // required fitness value for goal target line (0.0–1.0)
    let contextText: String

    @State private var selectedSnapshot: FitnessSnapshot? = nil
    @State private var showingDetail = false
    @State private var appeared = false

    private var peakValue: Double {
        snapshots.max(by: { $0.value < $1.value })?.value ?? 1.0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fitness history")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.enzoSecondary)
                .textCase(.uppercase)
                .tracking(1)

            chart
                .frame(height: 160)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
                .onAppear {
                    withAnimation(.easeOut(duration: 0.6)) {
                        appeared = true
                    }
                }
                .sheet(isPresented: $showingDetail) {
                    if let snap = selectedSnapshot {
                        MonthDetailSheet(snapshot: snap)
                    }
                }

            Text(contextText)
                .font(.system(.caption))
                .foregroundStyle(Color.enzoSecondary)
                .italic()
        }
        .padding()
        .background(Color.enzoCard, in: RoundedRectangle(cornerRadius: 16))
    }

    private var chart: some View {
        Chart {
            // Area fill
            ForEach(snapshots) { snap in
                AreaMark(
                    x: .value("Month", snap.monthDate),
                    y: .value("Fitness", snap.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.enzoAccent.opacity(0.25), Color.enzoAccent.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
            }

            // Line
            ForEach(snapshots) { snap in
                LineMark(
                    x: .value("Month", snap.monthDate),
                    y: .value("Fitness", snap.value)
                )
                .foregroundStyle(Color.enzoAccent)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.catmullRom)
            }

            // Current position dot
            if let current = snapshots.last {
                PointMark(
                    x: .value("Month", current.monthDate),
                    y: .value("Fitness", current.value)
                )
                .foregroundStyle(Color.enzoAccent)
                .symbolSize(60)
            }

            // Peak reference line
            RuleMark(y: .value("Peak", peakValue))
                .foregroundStyle(Color.enzoSecondary.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .annotation(position: .top, alignment: .trailing) {
                    Text("Your peak")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.enzoSecondary)
                        .padding(.trailing, 4)
                }

            // Goal target reference line
            RuleMark(y: .value("Goal target", goalValue))
                .foregroundStyle(Color.enzoGoal.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .annotation(position: .top, alignment: .leading) {
                    Text("Goal target")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.enzoGoal)
                        .padding(.leading, 4)
                }

            // Selected month highlight
            if let sel = selectedSnapshot {
                RuleMark(x: .value("Selected", sel.monthDate))
                    .foregroundStyle(Color.enzoPrimary.opacity(0.15))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
        }
        .chartYScale(domain: 0...1.1)
        .chartXAxis {
            AxisMarks(values: .stride(by: .month, count: 3)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Color.enzoSecondary)
            }
        }
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
                            let closest = snapshots.min {
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
}

#Preview {
    FitnessChartView(
        snapshots: FitnessSnapshot.previewSnapshots,
        goalValue: 0.70,
        contextText: AthleteContext.previewChartContext
    )
    .padding()
    .background(Color.enzoBg)
    .preferredColorScheme(.dark)
}
