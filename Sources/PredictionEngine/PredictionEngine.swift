import Foundation
import SharedModels
import HistoryEngine

// MARK: - Prediction Engine

@Observable
public final class PredictionEngine: @unchecked Sendable {
    private let history: HistoryEngine

    // Scoring weights
    private var weights = ScoringWeights()

    public init(history: HistoryEngine) {
        self.history = history
    }

    // MARK: - Predict

    public func predict(
        prefix: String,
        currentDirectory: String,
        previousCommand: String? = nil,
        projectType: ProjectType? = nil,
        limit: Int = 10
    ) -> [Prediction] {
        guard !prefix.isEmpty else { return [] }

        // Gather candidates from history
        let candidates: [String]
        do {
            let entries = try history.search(query: prefix, limit: 200)
            candidates = Array(Set(entries.map(\.command)))
        } catch {
            return []
        }

        // Score each candidate
        var predictions: [Prediction] = []

        let frequencyMap: [String: Int]
        do {
            frequencyMap = try history.frequencyMap()
        } catch {
            return []
        }

        let maxFreq = frequencyMap.values.max() ?? 1

        for candidate in candidates {
            let freqScore = frequencyScore(
                count: frequencyMap[candidate] ?? 0,
                maxCount: maxFreq
            )
            let prefixScore = prefixMatchScore(candidate: candidate, prefix: prefix)
            let dirScore = directoryScore(candidate: candidate, directory: currentDirectory)

            let totalScore =
                weights.frequency * freqScore +
                weights.prefix * prefixScore +
                weights.directory * dirScore

            if totalScore > 0.1 {
                predictions.append(Prediction(
                    command: candidate,
                    score: totalScore,
                    source: .frequencyHistory
                ))
            }
        }

        predictions.sort { $0.score > $1.score }
        return Array(predictions.prefix(limit))
    }

    // MARK: - Scoring Functions

    private func frequencyScore(count: Int, maxCount: Int) -> Double {
        guard maxCount > 0 else { return 0 }
        return min(1.0, log2(Double(count + 1)) / log2(Double(maxCount + 1)))
    }

    private func prefixMatchScore(candidate: String, prefix: String) -> Double {
        if candidate.hasPrefix(prefix) { return 1.0 }
        if candidate.lowercased().hasPrefix(prefix.lowercased()) { return 0.7 }
        if candidate.lowercased().contains(prefix.lowercased()) { return 0.3 }
        return 0.0
    }

    private func directoryScore(candidate: String, directory: String) -> Double {
        // Simplified: would check history for directory-specific frequency
        return 0.5
    }

    // MARK: - Feedback

    public func recordFeedback(prediction: String, accepted: Bool, context: PredictionContext) {
        // Store feedback for adaptive weighting
    }
}

// MARK: - Scoring Weights

struct ScoringWeights {
    var frequency: Double = 0.20
    var recency: Double = 0.15
    var prefix: Double = 0.25
    var directory: Double = 0.15
    var projectType: Double = 0.10
    var ngram: Double = 0.10
    var feedback: Double = 0.05
}
