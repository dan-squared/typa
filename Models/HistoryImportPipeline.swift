import Foundation
import SwiftData

struct HistoryImportReport: Equatable, Sendable {
    var importedCount: Int
    var repairedCount: Int
    var discardedCount: Int
    var duplicateCount: Int
    var discardedReasons: [TypingResultDiscardReason: Int] = [:]

    var summaryText: String {
        var parts = ["Imported \(importedCount)"]
        if repairedCount > 0 {
            parts.append("repaired \(repairedCount)")
        }
        if duplicateCount > 0 {
            parts.append("duplicates \(duplicateCount)")
        }
        if discardedCount > 0 {
            let reasonSummary = discardedReasons
                .sorted { lhs, rhs in
                    if lhs.value == rhs.value {
                        return lhs.key.rawValue < rhs.key.rawValue
                    }
                    return lhs.value > rhs.value
                }
                .map { "\($0.value) \($0.key.summaryLabel)" }
                .joined(separator: ", ")
            if reasonSummary.isEmpty {
                parts.append("skipped \(discardedCount)")
            } else {
                parts.append("skipped \(discardedCount) (\(reasonSummary))")
            }
        }
        return parts.joined(separator: " · ")
    }
}

struct HistoryImportLoadResult: Equatable, Sendable {
    var sessions: [HistoryTransferSession]
    var discardedRowCount: Int = 0
}

extension HistoryTransferPackage {
    private enum PackageCodingKeys: String, CodingKey {
        case formatVersion
        case exportedAt
        case sessions
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: PackageCodingKeys.self)
        formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        exportedAt = try container.decode(Date.self, forKey: .exportedAt)
        sessions = try container.decode([HistoryTransferSession].self, forKey: .sessions)
    }

    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: PackageCodingKeys.self)
        try container.encode(formatVersion, forKey: .formatVersion)
        try container.encode(exportedAt, forKey: .exportedAt)
        try container.encode(sessions, forKey: .sessions)
    }
}

enum HistoryImportPipeline {
    nonisolated static func normalizedSessions(
        from sessions: [HistoryTransferSession],
        now: Date = .now
    ) -> (
        sessions: [HistoryTransferSession],
        repairedCount: Int,
        discardedCount: Int,
        discardedReasons: [TypingResultDiscardReason: Int]
    ) {
        HistoryImportSupport.normalizeImportedSessions(sessions, now: now)
    }

    nonisolated static func loadSessions(from fileURL: URL) throws -> [HistoryTransferSession] {
        try loadSessionBatch(from: fileURL).sessions
    }

    nonisolated static func loadSessionBatch(from fileURL: URL) throws -> HistoryImportLoadResult {
        let didAccessResource = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didAccessResource {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        let payload = try Data(contentsOf: fileURL)
        if fileURL.pathExtension.lowercased() == "json" {
            return HistoryImportLoadResult(sessions: try decodeJSONSessions(from: payload))
        }

        if let decoded = try decodeJSONIfPossible(from: payload) {
            return HistoryImportLoadResult(sessions: decoded)
        }

        return try decodeLegacyCSV(from: payload)
    }

    nonisolated private static func decodeJSONIfPossible(from data: Data) throws -> [HistoryTransferSession]? {
        do {
            return try decodeJSONSessions(from: data)
        } catch {
            let text = String(decoding: data, as: UTF8.self)
            guard text.contains(",") else {
                throw error
            }
            return nil
        }
    }

    nonisolated private static func decodeJSONSessions(from data: Data) throws -> [HistoryTransferSession] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let package = try? decoder.decode(HistoryTransferPackage.self, from: data) {
            return package.sessions
        }

        return try decoder.decode([HistoryTransferSession].self, from: data)
    }

    nonisolated private static func decodeLegacyCSV(from data: Data) throws -> HistoryImportLoadResult {
        let text = String(decoding: data, as: UTF8.self)
        let rows = try parseCSVRows(text)
            .filter { row in
                !row.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            }

        guard !rows.isEmpty else { return HistoryImportLoadResult(sessions: []) }
        var sessions: [HistoryTransferSession] = []
        var discardedRowCount = 0

        for row in rows {
            let normalizedHeader = row
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            if normalizedHeader.starts(with: ["date", "mode", "duration"]) {
                continue
            }

            guard row.count >= 6 else {
                discardedRowCount += 1
                continue
            }

            guard let date = parseDate(row[0]) else {
                discardedRowCount += 1
                continue
            }

            let mode = row[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let duration = Double(row[2].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            let wpm = Double(row[3].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            let accuracy = Double(row[4].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            let errors = Int(row[5].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            let words = max(1, Int((duration / 60.0) * max(1, wpm)))

            sessions.append(
                HistoryTransferSession(
                    date: date,
                    mode: mode,
                    duration: duration,
                    words: words,
                    wpm: wpm,
                    accuracy: accuracy,
                    rawInput: "",
                    errors: errors,
                    adaptivePayloadJSON: nil
                )
            )
        }

        return HistoryImportLoadResult(
            sessions: sessions,
            discardedRowCount: discardedRowCount
        )
    }

    nonisolated private static func parseDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return HistoryImportDateParserCache.parse(trimmed)
    }

    nonisolated private static func parseCSVRows(_ text: String) throws -> [[String]] {
        enum CSVError: Error {
            case unterminatedQuotedField
        }

        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var isInsideQuotes = false
        let characters = Array(text)
        var index = 0

        while index < characters.count {
            let character = characters[index]

            if isInsideQuotes {
                if character == "\"" {
                    let nextIndex = index + 1
                    if nextIndex < characters.count, characters[nextIndex] == "\"" {
                        currentField.append("\"")
                        index += 1
                    } else {
                        isInsideQuotes = false
                    }
                } else {
                    currentField.append(character)
                }
                index += 1
                continue
            }

            switch character {
            case "\"":
                isInsideQuotes = true
            case ",":
                currentRow.append(currentField)
                currentField = ""
            case "\n":
                currentRow.append(currentField)
                rows.append(currentRow)
                currentRow = []
                currentField = ""
            case "\r":
                currentRow.append(currentField)
                rows.append(currentRow)
                currentRow = []
                currentField = ""
                if index + 1 < characters.count, characters[index + 1] == "\n" {
                    index += 1
                }
            default:
                currentField.append(character)
            }

            index += 1
        }

        guard !isInsideQuotes else {
            throw CSVError.unterminatedQuotedField
        }

        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField)
            rows.append(currentRow)
        }

        return rows
    }
}

private enum HistoryImportDateParserCache {
    static let lock = NSLock()
    static let iso8601 = ISO8601DateFormatter()
    static let formatters: [DateFormatter] = {
        [
            "yyyy-MM-dd HH:mm:ss Z",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "MMM d, yyyy 'at' h:mm:ss a"
        ].map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            return formatter
        }
    }()

    static func parse(_ value: String) -> Date? {
        lock.lock()
        defer { lock.unlock() }

        if let date = iso8601.date(from: value) {
            return date
        }

        for formatter in formatters {
            if let date = formatter.date(from: value) {
                return date
            }
        }

        return nil
    }
}

private enum HistoryImportSupport {
    nonisolated static func normalizeImportedSessions(
        _ sessions: [HistoryTransferSession],
        now: Date = .now
    ) -> (
        sessions: [HistoryTransferSession],
        repairedCount: Int,
        discardedCount: Int,
        discardedReasons: [TypingResultDiscardReason: Int]
    ) {
        var normalized: [HistoryTransferSession] = []
        normalized.reserveCapacity(sessions.count)

        var repairedCount = 0
        var discardedCount = 0
        var discardedReasons: [TypingResultDiscardReason: Int] = [:]

        for session in sessions {
            let outcome = TypingResultRecovery.normalizedOutcome(for: session, now: now)
            guard let draft = outcome.draft else {
                discardedCount += 1
                if let reason = outcome.discardReason {
                    discardedReasons[reason, default: 0] += 1
                }
                continue
            }
            if outcome.wasRepaired {
                repairedCount += 1
            }
            normalized.append(
                HistoryTransferSession(
                    date: draft.date,
                    mode: draft.mode,
                    duration: draft.duration,
                    words: draft.words,
                    wpm: draft.wpm,
                    accuracy: draft.accuracy,
                    rawInput: draft.rawInput,
                    errors: draft.errors,
                    adaptivePayloadJSON: draft.adaptivePayloadJSON
                )
            )
        }

        return (normalized, repairedCount, discardedCount, discardedReasons)
    }
}

private enum HistoryDeduplication {
    nonisolated static func stableID(
        timestampMS: Int64,
        mode: String,
        durationMS: Int,
        words: Int,
        wpmHundredths: Int,
        accuracyHundredths: Int,
        rawInput: String,
        errors: Int,
        adaptivePayloadJSON: String?
    ) -> String {
        [
            String(timestampMS),
            mode,
            String(durationMS),
            String(words),
            String(wpmHundredths),
            String(accuracyHundredths),
            rawInput,
            String(errors),
            adaptivePayloadJSON ?? ""
        ].joined(separator: "|")
    }

    nonisolated static func stableID(for session: HistoryTransferSession) -> String {
        stableID(
            timestampMS: Int64((session.date.timeIntervalSince1970 * 1_000).rounded()),
            mode: session.mode,
            durationMS: Int((session.duration * 1_000).rounded()),
            words: session.words,
            wpmHundredths: Int((session.wpm * 100).rounded()),
            accuracyHundredths: Int((session.accuracy * 100).rounded()),
            rawInput: session.rawInput,
            errors: session.errors,
            adaptivePayloadJSON: session.adaptivePayloadJSON
        )
    }

    nonisolated static func stableID(for key: HistoryTransferDeduplicationKey) -> String {
        stableID(
            timestampMS: key.timestampMS,
            mode: key.mode,
            durationMS: key.durationMS,
            words: key.words,
            wpmHundredths: key.wpmHundredths,
            accuracyHundredths: key.accuracyHundredths,
            rawInput: key.rawInput,
            errors: key.errors,
            adaptivePayloadJSON: key.adaptivePayloadJSON
        )
    }
}

@ModelActor
actor HistoryStoreActor {
    func fetchSessions() throws -> [HistoryTransferSession] {
        var sessions: [HistoryTransferSession] = []
        var needsBackfillSave = false
        var offset = 0
        let limit = 1000

        while true {
            var descriptor = FetchDescriptor<TypingResult>(
                sortBy: [SortDescriptor(\.date, order: .forward)]
            )
            descriptor.fetchLimit = limit
            descriptor.fetchOffset = offset

            let results = try modelContext.fetch(descriptor)
            if results.isEmpty { break }

            for result in results {
                let session = rawSessionSnapshot(from: result)
                let stableID = HistoryDeduplication.stableID(for: session)
                if result.deduplicationID != stableID {
                    result.deduplicationID = stableID
                    needsBackfillSave = true
                }
                sessions.append(session)
            }

            offset += limit
        }

        if needsBackfillSave {
            try modelContext.save()
        }

        return sessions
    }

    func saveDraft(_ draft: NormalizedTypingResultDraft) throws -> HistoryTransferSession {
        let session = HistoryTransferSession(
            date: draft.date,
            mode: draft.mode,
            duration: draft.duration,
            words: draft.words,
            wpm: draft.wpm,
            accuracy: draft.accuracy,
            rawInput: draft.rawInput,
            errors: draft.errors,
            adaptivePayloadJSON: draft.adaptivePayloadJSON
        )
        if try fetchStoredResult(withStableDeduplicationID: HistoryDeduplication.stableID(for: session)) != nil {
            return session
        }
        modelContext.insert(
            TypingResult(
                date: session.date,
                mode: session.mode,
                duration: session.duration,
                words: session.words,
                wpm: session.wpm,
                accuracy: session.accuracy,
                rawInput: session.rawInput,
                errors: session.errors,
                adaptivePayloadJSON: session.adaptivePayloadJSON,
                deduplicationID: HistoryDeduplication.stableID(for: session)
            )
        )
        try modelContext.save()
        return session
    }

    func deleteSession(matching deduplicationKey: HistoryTransferDeduplicationKey) throws -> Bool {
        guard let target = try fetchExistingResult(matching: deduplicationKey) else {
            return false
        }

        modelContext.delete(target)
        try modelContext.save()
        return true
    }

    func deleteAllSessions() throws -> Int {
        let results = try modelContext.fetch(FetchDescriptor<TypingResult>())
        guard !results.isEmpty else { return 0 }

        for result in results {
            modelContext.delete(result)
        }
        try modelContext.save()
        return results.count
    }

    func importSessions(_ sessions: [HistoryTransferSession]) async throws -> HistoryImportReport {
        let normalizedBatch = HistoryImportSupport.normalizeImportedSessions(sessions)
        var seenImportedIDs = Set<String>()
        var legacyCandidates: [TypingResult]?
        var needsBackfillSave = false
        var importedCount = 0
        var duplicateCount = 0

        for normalized in normalizedBatch.sessions {
            let deduplicationID = HistoryDeduplication.stableID(for: normalized)
            guard seenImportedIDs.insert(deduplicationID).inserted else {
                duplicateCount += 1
                continue
            }
            if try fetchExistingResult(
                matchingStableDeduplicationID: deduplicationID,
                legacyCandidates: &legacyCandidates,
                needsBackfillSave: &needsBackfillSave
            ) != nil {
                duplicateCount += 1
                continue
            }

            modelContext.insert(
                TypingResult(
                    date: normalized.date,
                    mode: normalized.mode,
                    duration: normalized.duration,
                    words: normalized.words,
                    wpm: normalized.wpm,
                    accuracy: normalized.accuracy,
                    rawInput: normalized.rawInput,
                    errors: normalized.errors,
                    adaptivePayloadJSON: normalized.adaptivePayloadJSON,
                    deduplicationID: deduplicationID
                )
            )
            importedCount += 1
        }

        if importedCount > 0 || needsBackfillSave {
            try modelContext.save()
        }

        return HistoryImportReport(
            importedCount: importedCount,
            repairedCount: normalizedBatch.repairedCount,
            discardedCount: normalizedBatch.discardedCount,
            duplicateCount: duplicateCount,
            discardedReasons: normalizedBatch.discardedReasons
        )
    }

    private func fetchExistingResult(
        matchingStableDeduplicationID stableID: String,
        legacyCandidates: inout [TypingResult]?,
        needsBackfillSave: inout Bool
    ) throws -> TypingResult? {
        if let stored = try fetchStoredResult(withStableDeduplicationID: stableID) {
            return stored
        }

        if legacyCandidates == nil {
            legacyCandidates = try modelContext.fetch(
                FetchDescriptor<TypingResult>(
                    predicate: #Predicate<TypingResult> { $0.deduplicationID == nil }
                )
            )
        }

        guard let index = legacyCandidates?.firstIndex(where: {
            HistoryDeduplication.stableID(for: rawSessionSnapshot(from: $0)) == stableID
        }),
              let target = legacyCandidates?[index] else {
            return nil
        }

        target.deduplicationID = stableID
        needsBackfillSave = true
        legacyCandidates?.remove(at: index)
        return target
    }

    private func fetchExistingResult(matching deduplicationKey: HistoryTransferDeduplicationKey) throws -> TypingResult? {
        let stableDeduplicationID = HistoryDeduplication.stableID(for: deduplicationKey)
        var legacyCandidates: [TypingResult]?
        var needsBackfillSave = false
        let result = try fetchExistingResult(
            matchingStableDeduplicationID: stableDeduplicationID,
            legacyCandidates: &legacyCandidates,
            needsBackfillSave: &needsBackfillSave
        )
        if needsBackfillSave {
            try modelContext.save()
        }
        return result
    }

    private func fetchStoredResult(withStableDeduplicationID stableID: String) throws -> TypingResult? {
        try modelContext.fetch(
            FetchDescriptor<TypingResult>(
                predicate: #Predicate<TypingResult> { $0.deduplicationID == stableID }
            )
        ).first
    }

    private func rawSessionSnapshot(from result: TypingResult) -> HistoryTransferSession {
        HistoryTransferSession(
            date: result.date,
            mode: result.mode,
            duration: result.duration,
            words: result.words,
            wpm: result.wpm,
            accuracy: result.accuracy,
            rawInput: result.rawInput,
            errors: result.errors,
            adaptivePayloadJSON: result.adaptivePayloadJSON
        )
    }
}
