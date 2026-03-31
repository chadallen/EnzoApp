import SwiftUI

struct SegmentDetailView: View {
    let segment: SegmentScore
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var hasTargetDate = false
    @State private var targetDate = Calendar.current.date(byAdding: .weekOfYear, value: 6, to: Date()) ?? Date()

    private var pillColor: Color {
        switch segment.strikeScore {
        case 0.70...: return .enzoGoal
        case 0.45..<0.70: return .enzoAmber
        default: return .enzoSecondary
        }
    }

    private var strikeLine: String {
        switch segment.strikeScore {
        case 0.70...:
            return "You're fit and trending in the right direction. A good window to go after it."
        case 0.45..<0.70:
            return "Getting close — a few more weeks of consistent riding and the timing will be right."
        default:
            return "Not quite there yet. Worth targeting once you've built more fitness."
        }
    }

    var body: some View {
        ZStack {
            Color.enzoBg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 6) {
                        if segment.isGoalSegment {
                            Label("Goal segment", systemImage: "star.fill")
                                .font(.system(.caption, design: .rounded, weight: .semibold))
                                .foregroundStyle(Color.enzoAccent)
                        }
                        Text(segment.name)
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .foregroundStyle(Color.enzoPrimary)
                    }

                    // Segment stats card
                    VStack(spacing: 12) {
                        HStack(spacing: 0) {
                            statBlock(value: segment.prFormatted, label: "Current PR", mono: true, color: Color.enzoAccent)
                            statBlock(value: formattedPRDate(segment.prDate), label: "Date set")
                        }

                        if segment.distanceMeters != nil || segment.elevationDeltaMeters != nil {
                            Rectangle()
                                .fill(Color.enzoSecondary.opacity(0.12))
                                .frame(height: 1)

                            HStack(spacing: 0) {
                                if let dist = segment.distanceMeters {
                                    statBlock(value: String(format: "%.1f mi", dist * 0.000621371), label: "Distance")
                                }
                                if let elev = segment.elevationDeltaMeters {
                                    statBlock(value: String(format: "+%.0f ft", elev * 3.28084), label: "Elevation gain")
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color.enzoCard, in: RoundedRectangle(cornerRadius: 16))

                    // Readiness assessment
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Readiness score")
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(Color.enzoSecondary)
                            .textCase(.uppercase)
                            .tracking(1)

                        HStack {
                            Text(segment.strikeLabel)
                                .font(.system(.title3, design: .rounded, weight: .bold))
                                .foregroundStyle(pillColor)
                            Spacer()
                            Text(String(format: "%.0f", segment.strikeScore * 100))
                                .font(.system(.title3, design: .monospaced, weight: .bold))
                                .foregroundStyle(pillColor)
                        }
                        Text(strikeLine)
                            .font(.system(.subheadline))
                            .foregroundStyle(Color.enzoSecondary)
                            .lineSpacing(3)
                    }
                    .padding()
                    .background(Color.enzoCard, in: RoundedRectangle(cornerRadius: 16))

                    // Goal card
                    if segment.isGoalSegment {
                        HStack(spacing: 8) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.enzoAccent)
                            Text("This is your current goal")
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .foregroundStyle(Color.enzoAccent)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.enzoAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle(isOn: $hasTargetDate) {
                                Text("Set a target date")
                                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                    .foregroundStyle(Color.enzoPrimary)
                            }
                            .tint(Color.enzoAccent)

                            if hasTargetDate {
                                DatePicker(
                                    "Target date",
                                    selection: $targetDate,
                                    in: Date()...,
                                    displayedComponents: .date
                                )
                                .datePickerStyle(.compact)
                                .foregroundStyle(Color.enzoPrimary)
                            }

                            Button {
                                appState.setGoal(segment, targetDate: hasTargetDate ? targetDate : nil)
                                Task {
                                    await appState.generateBriefing(forceRefresh: true)
                                    await appState.generateLookahead(forceRefresh: true)
                                }
                                dismiss()
                            } label: {
                                Text("Set this goal")
                                    .font(.system(.body, design: .rounded, weight: .bold))
                                    .foregroundStyle(Color.enzoBg)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.enzoAccent, in: RoundedRectangle(cornerRadius: 14))
                            }
                        }
                        .padding()
                        .background(Color.enzoCard, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
                .padding()
            }
        }
        .navigationTitle(segment.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.enzoBg, for: .navigationBar)
    }

    private func statBlock(value: String, label: String, mono: Bool = false, color: Color = Color.enzoPrimary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(mono ? .system(.title2, design: .monospaced, weight: .bold) : .system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.enzoSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formattedPRDate(_ dateString: String) -> String {
        let input = DateFormatter()
        input.dateFormat = "yyyy-MM-dd"
        input.timeZone = TimeZone(identifier: "UTC")
        guard let date = input.date(from: dateString) else { return dateString }
        let output = DateFormatter()
        output.dateStyle = .medium
        output.timeStyle = .none
        return output.string(from: date)
    }
}

#Preview {
    NavigationStack {
        SegmentDetailView(segment: SegmentScore.previewSegments[0])
    }
    .environment(AppState())
}
