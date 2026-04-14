import Foundation
import SharedModels
import AIService
import DataStore
import Accelerate

// MARK: - Semantic Search Result

public struct SemanticSearchResult: Sendable {
    public let commandEntry: CommandEntry?
    public let savedCommand: SavedCommand?
    public let similarity: Float
    public let matchedText: String

    public init(
        commandEntry: CommandEntry? = nil,
        savedCommand: SavedCommand? = nil,
        similarity: Float,
        matchedText: String
    ) {
        self.commandEntry = commandEntry
        self.savedCommand = savedCommand
        self.similarity = similarity
        self.matchedText = matchedText
    }
}

// MARK: - Embedding Pipeline

public actor EmbeddingPipeline {
    private let aiService: AIServiceClient
    private let dataAccess: DataAccess

    public init(aiService: AIServiceClient, dataAccess: DataAccess) {
        self.aiService = aiService
        self.dataAccess = dataAccess
    }

    // MARK: - Index Commands

    public func indexCommands(_ entries: [CommandEntry]) async throws {
        guard !entries.isEmpty else { return }

        let texts = entries.map { buildEmbeddingText(for: $0) }

        let embeddings = try await aiService.embeddings(
            input: texts,
            model: DefaultModels.embedding
        )

        for (entry, embedding) in zip(entries, embeddings) {
            let embeddingData = embedding.withUnsafeBufferPointer {
                Data(buffer: $0)
            }

            try dataAccess.db.execute(
                """
                INSERT OR REPLACE INTO command_embeddings
                    (id, command_history_id, content_text, embedding, model, created_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                parameters: [
                    .text(UUID().uuidString),
                    .text(entry.id),
                    .text(texts[0]),
                    .blob(embeddingData),
                    .text(DefaultModels.embedding.modelID),
                    .real(Date().timeIntervalSince1970),
                ]
            )
        }
    }

    // MARK: - Semantic Search

    public func search(query: String, limit: Int = 20) async throws -> [SemanticSearchResult] {
        // Get query embedding
        let queryEmbeddings = try await aiService.embeddings(
            input: [query],
            model: DefaultModels.embedding
        )

        guard let queryVector = queryEmbeddings.first else { return [] }

        // Load all stored embeddings
        let rows = try dataAccess.db.query(
            "SELECT id, command_history_id, saved_command_id, content_text, embedding FROM command_embeddings"
        )

        var results: [SemanticSearchResult] = []

        for row in rows {
            guard let contentText = row["content_text"]?.stringValue,
                  let embeddingData = row["embedding"]?.blobValue else {
                continue
            }

            let storedVector = embeddingData.withUnsafeBytes {
                Array($0.bindMemory(to: Float.self))
            }

            let similarity = cosineSimilarity(queryVector, storedVector)

            results.append(SemanticSearchResult(
                similarity: similarity,
                matchedText: contentText
            ))
        }

        results.sort { $0.similarity > $1.similarity }
        return Array(results.prefix(limit))
    }

    // MARK: - Indexed Count

    public func indexedCount() throws -> Int {
        let result = try dataAccess.db.scalar("SELECT COUNT(*) FROM command_embeddings")
        return Int(result.intValue ?? 0)
    }

    // MARK: - Private

    private func buildEmbeddingText(for entry: CommandEntry) -> String {
        var text = "Command: \(entry.command)"
        text += "\nDirectory: \(entry.workingDirectory)"
        if let projectType = entry.projectType {
            text += "\nProject: \(projectType.rawValue)"
        }
        return text
    }

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
        vDSP_svesq(a, 1, &normA, vDSP_Length(a.count))
        vDSP_svesq(b, 1, &normB, vDSP_Length(b.count))

        let denom = sqrt(normA) * sqrt(normB)
        return denom == 0 ? 0 : dot / denom
    }
}
