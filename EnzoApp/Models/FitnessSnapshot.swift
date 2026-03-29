import Foundation

struct FitnessSnapshot: Identifiable {
    let month: String  // "2025-08"
    let score: Double
    let hours: Double
    let rides: Int

    var id: String { month }

    var monthDate: Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        return f.date(from: month) ?? .distantPast
    }

    var shortMonthLabel: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        guard let date = f.date(from: month) else { return month }
        let display = DateFormatter()
        display.dateFormat = "MMM"
        return display.string(from: date)
    }

    var monthYearLabel: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        guard let date = f.date(from: month) else { return month }
        let display = DateFormatter()
        display.dateFormat = "MMMM yyyy"
        return display.string(from: date)
    }

    // MARK: - Hardcoded preview data (Section 18)

    static let previewSnapshots: [FitnessSnapshot] = [
        FitnessSnapshot(month: "2024-10", score: 24,  hours: 7.6,  rides: 7),
        FitnessSnapshot(month: "2024-11", score: 12,  hours: 4.1,  rides: 4),
        FitnessSnapshot(month: "2024-12", score: 13,  hours: 4.3,  rides: 4),
        FitnessSnapshot(month: "2025-01", score: 21,  hours: 6.7,  rides: 5),
        FitnessSnapshot(month: "2025-02", score: 14,  hours: 4.7,  rides: 3),
        FitnessSnapshot(month: "2025-03", score: 69,  hours: 21.2, rides: 10),
        FitnessSnapshot(month: "2025-04", score: 72,  hours: 22.1, rides: 8),
        FitnessSnapshot(month: "2025-05", score: 36,  hours: 11.1, rides: 8),
        FitnessSnapshot(month: "2025-06", score: 39,  hours: 12.1, rides: 9),
        FitnessSnapshot(month: "2025-07", score: 45,  hours: 13.9, rides: 7),
        FitnessSnapshot(month: "2025-08", score: 100, hours: 30.4, rides: 13),  // peak
        FitnessSnapshot(month: "2025-09", score: 4,   hours: 1.6,  rides: 2),   // sharp drop
        FitnessSnapshot(month: "2025-10", score: 58,  hours: 17.6, rides: 18),
        FitnessSnapshot(month: "2025-11", score: 37,  hours: 11.6, rides: 8),
        FitnessSnapshot(month: "2025-12", score: 26,  hours: 8.1,  rides: 8),
        FitnessSnapshot(month: "2026-01", score: 26,  hours: 8.2,  rides: 6),
        FitnessSnapshot(month: "2026-02", score: 26,  hours: 8.3,  rides: 5),
        FitnessSnapshot(month: "2026-03", score: 20,  hours: 6.4,  rides: 6),   // current
    ]
}
