import Foundation

enum PracticeContentLibrary {
    static let fallbackWords: [String] = ["the", "and", "that", "with", "from"]

    static let codeWords: [String] = [
        "func", "struct", "class", "actor", "await", "async", "guard", "switch",
        "return", "throws", "result", "state", "render", "layout", "cursor", "target",
        "option", "config", "profile", "module", "import", "public", "private", "static",
        "const", "let", "var", "value", "index", "array", "queue", "cache",
        "model", "screen", "button", "window", "event", "update", "branch", "commit"
    ]

    static func diversifiedTestWords(
        from words: [String],
        count: Int
    ) -> [String] {
        let uniqueWords = uniqueOrderedWords(from: words)
        guard !uniqueWords.isEmpty else { return fallbackWords }
        guard count > 0 else { return uniqueWords }
        guard uniqueWords.count > 1 else {
            return Array(repeating: uniqueWords[0], count: count)
        }

        var generator = SystemRandomNumberGenerator()
        var prepared: [String] = []
        prepared.reserveCapacity(count)
        var recentWords: [String] = []
        var usageCount: [String: Int] = [:]

        while prepared.count < count {
            let nextWord = weightedSample(
                from: uniqueWords,
                recentWords: recentWords,
                usageCount: usageCount,
                generator: &generator
            ) ?? uniqueWords.randomElement(using: &generator) ?? fallbackWords[0]

            prepared.append(nextWord)
            usageCount[nextWord, default: 0] += 1
            recentWords.append(nextWord)
            if recentWords.count > 3 {
                recentWords.removeFirst(recentWords.count - 3)
            }
        }

        return prepared
    }

    private static func uniqueOrderedWords(from words: [String]) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        ordered.reserveCapacity(words.count)

        for word in words where !word.isEmpty {
            guard seen.insert(word).inserted else { continue }
            ordered.append(word)
        }

        return ordered
    }

    private static func weightedSample<T: RandomNumberGenerator>(
        from words: [String],
        recentWords: [String],
        usageCount: [String: Int],
        generator: inout T
    ) -> String? {
        let recentSet = Set(recentWords)
        var totalWeight = 0.0
        var weightedWords: [(word: String, total: Double)] = []
        weightedWords.reserveCapacity(words.count)

        for (index, word) in words.enumerated() {
            let rankWeight = 1.0 / sqrt(Double(index + 1))
            let repetitionPenalty = 1.0 / (1.0 + Double(usageCount[word, default: 0]) * 1.35)
            let recentPenalty = recentSet.contains(word) ? 0.18 : 1.0
            let weight = rankWeight * repetitionPenalty * recentPenalty

            guard weight > 0 else { continue }
            totalWeight += weight
            weightedWords.append((word, totalWeight))
        }

        guard totalWeight > 0 else { return nil }

        let threshold = Double.random(in: 0..<totalWeight, using: &generator)
        for candidate in weightedWords where threshold < candidate.total {
            return candidate.word
        }

        return weightedWords.last?.word
    }
}
