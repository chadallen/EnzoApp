import Foundation

struct FitnessSnapshot: Identifiable {
    let month: String  // "2025-08"
    let label: String  // "Epic", "Strong", "Building", "Baseline", "Recovering"
    let value: Double  // 0.0–1.0 internal, never shown to user
    let hours: Double
    let rides: Int
    let trend: String  // "up", "flat", "down"

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

    nonisolated(unsafe) static let previewSnapshots: [FitnessSnapshot] = [
        FitnessSnapshot(month: "2024-10", label: "Baseline",   value: 0.24, hours: 7.6,  rides: 7,  trend: "flat"),
        FitnessSnapshot(month: "2024-11", label: "Recovering", value: 0.12, hours: 4.1,  rides: 4,  trend: "down"),
        FitnessSnapshot(month: "2024-12", label: "Recovering", value: 0.13, hours: 4.3,  rides: 4,  trend: "flat"),
        FitnessSnapshot(month: "2025-01", label: "Baseline",   value: 0.21, hours: 6.7,  rides: 5,  trend: "up"),
        FitnessSnapshot(month: "2025-02", label: "Recovering", value: 0.14, hours: 4.7,  rides: 3,  trend: "down"),
        FitnessSnapshot(month: "2025-03", label: "Building",   value: 0.69, hours: 21.2, rides: 10, trend: "up"),
        FitnessSnapshot(month: "2025-04", label: "Strong",     value: 0.72, hours: 22.1, rides: 8,  trend: "up"),
        FitnessSnapshot(month: "2025-05", label: "Baseline",   value: 0.36, hours: 11.1, rides: 8,  trend: "down"),
        FitnessSnapshot(month: "2025-06", label: "Baseline",   value: 0.39, hours: 12.1, rides: 9,  trend: "flat"),
        FitnessSnapshot(month: "2025-07", label: "Building",   value: 0.45, hours: 13.9, rides: 7,  trend: "up"),
        FitnessSnapshot(month: "2025-08", label: "Epic",       value: 1.00, hours: 30.4, rides: 13, trend: "up"),   // peak
        FitnessSnapshot(month: "2025-09", label: "Recovering", value: 0.04, hours: 1.6,  rides: 2,  trend: "down"), // sharp drop
        FitnessSnapshot(month: "2025-10", label: "Building",   value: 0.58, hours: 17.6, rides: 18, trend: "up"),
        FitnessSnapshot(month: "2025-11", label: "Baseline",   value: 0.37, hours: 11.6, rides: 8,  trend: "down"),
        FitnessSnapshot(month: "2025-12", label: "Baseline",   value: 0.26, hours: 8.1,  rides: 8,  trend: "flat"),
        FitnessSnapshot(month: "2026-01", label: "Baseline",   value: 0.26, hours: 8.2,  rides: 6,  trend: "flat"),
        FitnessSnapshot(month: "2026-02", label: "Baseline",   value: 0.26, hours: 8.3,  rides: 5,  trend: "flat"),
        FitnessSnapshot(month: "2026-03", label: "Recovering", value: 0.18, hours: 6.4,  rides: 6,  trend: "up"),   // current
    ]
}
