import SwiftUI

struct MonthDetailSheet: View {
    let snapshot: FitnessSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Handle bar
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.enzoSecondary.opacity(0.4))
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)

            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.monthYearLabel)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.enzoPrimary)

                Text(AthleteContext.fitnessLabel(for: snapshot.score))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.enzoAccent)
            }

            HStack(spacing: 0) {
                statBlock(
                    value: String(format: "%.0f", snapshot.score),
                    label: "Fitness score",
                    valueColor: Color.enzoAccent
                )

                Divider()
                    .frame(height: 40)
                    .background(Color.enzoSecondary.opacity(0.2))

                statBlock(
                    value: String(format: "%.1f h", snapshot.hours),
                    label: "Hours"
                )

                Divider()
                    .frame(height: 40)
                    .background(Color.enzoSecondary.opacity(0.2))

                statBlock(
                    value: "\(snapshot.rides)",
                    label: "Rides"
                )
            }

            Spacer()
        }
        .padding(.horizontal)
        .frame(maxWidth: .infinity, alignment: .leading)
        .presentationDetents([.fraction(0.32)])
        .presentationBackground(Color.enzoCard)
        .presentationCornerRadius(20)
    }

    private func statBlock(value: String, label: String, valueColor: Color = Color.enzoPrimary) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(.title2, design: .monospaced, weight: .bold))
                .foregroundStyle(valueColor)
            Text(label)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Color.enzoSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    MonthDetailSheet(snapshot: FitnessSnapshot.previewSnapshots[10])
        .background(Color.enzoBg)
}
