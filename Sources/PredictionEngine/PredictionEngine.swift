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

        // Pre-fetch n-gram predictions for context scoring
        let ngramPredictions: [(prediction: String, count: Int)]
        if let prev = previousCommand {
            ngramPredictions = (try? history.queryNgrams(context: prev)) ?? []
        } else {
            ngramPredictions = []
        }
        let ngramMap = Dictionary(ngramPredictions.map { ($0.prediction, $0.count) }, uniquingKeysWith: { a, _ in a })
        let maxNgramCount = ngramPredictions.map(\.count).max() ?? 1

        // Pre-fetch project type commands for batch scoring
        let projectCommands: Set<String>
        if let pt = projectType {
            projectCommands = Set((try? history.commandsInProjectType(pt)) ?? [])
        } else {
            projectCommands = []
        }

        for candidate in candidates {
            let freqScore = frequencyScore(
                count: frequencyMap[candidate] ?? 0,
                maxCount: maxFreq
            )
            let prefixScore = prefixMatchScore(candidate: candidate, prefix: prefix)
            let dirScore = directoryScore(candidate: candidate, directory: currentDirectory)
            let recScore = recencyScore(candidate: candidate)
            let projScore = projectTypeScore(candidate: candidate, projectCommands: projectCommands)
            let nScore = ngramScore(candidate: candidate, ngramMap: ngramMap, maxCount: maxNgramCount)

            let totalScore =
                weights.frequency * freqScore +
                weights.prefix * prefixScore +
                weights.directory * dirScore +
                weights.recency * recScore +
                weights.projectType * projScore +
                weights.ngram * nScore

            if totalScore > 0.1 {
                predictions.append(Prediction(
                    command: candidate,
                    score: totalScore,
                    source: determinePredictionSource(
                        freqScore: freqScore,
                        ngramScore: nScore,
                        dirScore: dirScore
                    )
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
        let freq = (try? history.commandFrequencyInDirectory(command: candidate, directory: directory)) ?? 0
        if freq > 0 {
            return min(1.0, log2(Double(freq + 1)) / log2(10.0))
        }

        // Check parent directory as fallback
        let parentDir = (directory as NSString).deletingLastPathComponent
        let parentFreq = (try? history.commandFrequencyInDirectory(command: candidate, directory: parentDir)) ?? 0
        if parentFreq > 0 {
            return 0.3
        }

        return 0.0
    }

    private func recencyScore(candidate: String) -> Double {
        guard let lastUsed = try? history.mostRecentExecution(command: candidate) else {
            return 0.0
        }
        let hoursAgo = Date().timeIntervalSince(lastUsed) / 3600.0
        // Decay over 1 week (168 hours)
        return max(0.0, 1.0 - hoursAgo / 168.0)
    }

    private func projectTypeScore(candidate: String, projectCommands: Set<String>) -> Double {
        guard !projectCommands.isEmpty else { return 0.0 }
        return projectCommands.contains(candidate) ? 1.0 : 0.0
    }

    private func ngramScore(candidate: String, ngramMap: [String: Int], maxCount: Int) -> Double {
        guard let count = ngramMap[candidate], maxCount > 0 else { return 0.0 }
        return min(1.0, Double(count) / Double(maxCount))
    }

    private func determinePredictionSource(freqScore: Double, ngramScore: Double, dirScore: Double) -> PredictionSource {
        if ngramScore > 0.5 { return .ngramSequence }
        if dirScore > 0.5 { return .directoryContext }
        return .frequencyHistory
    }

    // MARK: - Feedback

    public func recordFeedback(prediction: String, accepted: Bool, context: PredictionContext) {
        try? history.recordPredictionFeedback(
            predicted: prediction,
            accepted: accepted,
            directory: context.currentDirectory,
            previousCommand: context.previousCommand
        )
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
