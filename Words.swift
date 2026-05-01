import Foundation
import OSLog

enum Language: String, CaseIterable, Identifiable, Sendable {
    case english = "English"
    case english1k = "English 1k"
    case english5k = "English 5k"
    case english10k = "English 10k"
    case english25k = "English 25k"
    case englishCommonlyMisspelled = "English Commonly Misspelled"
    case englishShakespearean = "English Shakespearean"

    var id: String { rawValue }

    nonisolated func wordList() -> [String] {
        WordCorpusCatalog.shared.words(for: self)
    }

    nonisolated var phoneticModelResourceName: String {
        switch self {
        case .english,
             .english1k,
             .english5k,
             .english10k,
             .english25k,
             .englishCommonlyMisspelled,
             .englishShakespearean:
            return "model-en"
        }
    }
}

enum ResourceBundleCatalog {
    nonisolated static var candidateBundles: [Bundle] {
        var bundles: [Bundle] = [Bundle.main, Bundle(for: WordCorpusBundleSentinel.self)]
        bundles.append(contentsOf: Bundle.allBundles)
        bundles.append(contentsOf: Bundle.allFrameworks)

        var seen = Set<ObjectIdentifier>()
        return bundles.filter { bundle in
            let identifier = ObjectIdentifier(bundle)
            return seen.insert(identifier).inserted
        }
    }
}

final class WordCorpusCatalog: @unchecked Sendable {
    nonisolated static let shared = WordCorpusCatalog()

    nonisolated private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? AppIdentity.bundleIdentifier,
        category: "WordCorpus"
    )
    nonisolated private let lock = NSLock()
    nonisolated(unsafe) private var cachedCorpora: [Language: [String]]?
    nonisolated(unsafe) private var cachedInfrastructureNotice: AppInfrastructureNotice?

    nonisolated func prime() {
        _ = words(for: .english)
    }

    nonisolated var infrastructureNotice: AppInfrastructureNotice? {
        lock.lock()
        defer { lock.unlock() }

        if cachedCorpora == nil {
            cachedCorpora = loadCorpora()
        }

        return cachedInfrastructureNotice
    }

    nonisolated func words(for language: Language) -> [String] {
        lock.lock()
        defer { lock.unlock() }

        if cachedCorpora == nil {
            cachedCorpora = loadCorpora()
        }

        return cachedCorpora?[language] ?? Self.fallbackCorpora[language, default: Self.defaultFallbackWords]
    }

    nonisolated private func loadCorpora() -> [Language: [String]] {
        var locatedCorpusResource = false
        var firstFailureDescription: String?

        for bundle in ResourceBundleCatalog.candidateBundles {
            guard let url = bundle.url(forResource: "word-corpora", withExtension: "json") else { continue }
            locatedCorpusResource = true

            do {
                let data = try Data(contentsOf: url)
                let decoded = try JSONDecoder().decode([String: [String]].self, from: data)

                cachedInfrastructureNotice = nil
                var corpora: [Language: [String]] = [:]
                for language in Language.allCases {
                    corpora[language] = decoded[language.rawValue] ?? Self.fallbackCorpora[language, default: Self.defaultFallbackWords]
                }
                return corpora
            } catch {
                if firstFailureDescription == nil {
                    firstFailureDescription = error.localizedDescription
                }
                Self.logger.error(
                    "Failed to load word corpus from \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
                continue
            }
        }

        let message: String
        if locatedCorpusResource {
            let suffix = firstFailureDescription.map { " \($0)" } ?? ""
            message = "Word corpora could not be loaded. Falling back to the starter word list.\(suffix)"
        } else {
            message = "Word corpora resource was missing. Falling back to the starter word list."
        }

        cachedInfrastructureNotice = AppInfrastructureNotice(
            source: .resources,
            kind: .warning,
            title: "Limited Word Corpus",
            message: message
        )
        Self.logger.error("\(message, privacy: .public)")
        #if DEBUG
        assertionFailure(message)
        #endif

        return Self.fallbackCorpora
    }

    nonisolated private static let defaultFallbackWords = PracticeContentLibrary.fallbackWords

    nonisolated private static let fallbackCorpora: [Language: [String]] = [
        .english: defaultFallbackWords,
        .english1k: defaultFallbackWords,
        .english5k: defaultFallbackWords,
        .english10k: defaultFallbackWords,
        .english25k: defaultFallbackWords,
        .englishCommonlyMisspelled: ["accommodate", "occurred", "embarrass", "millennium", "necessary"],
        .englishShakespearean: ["thee", "thou", "thy", "wherefore", "hath"]
    ]
}

private final class WordCorpusBundleSentinel: NSObject {}
