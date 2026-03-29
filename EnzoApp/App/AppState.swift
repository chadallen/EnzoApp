import Observation

@Observable
@MainActor
class AppState {
    var athleteContext: AthleteContext = .preview
    var fitnessSnapshots: [FitnessSnapshot] = FitnessSnapshot.previewSnapshots
    var segments: [SegmentScore] = SegmentScore.previewSegments
    var arcMessages: [ArcMessage] = []
}
