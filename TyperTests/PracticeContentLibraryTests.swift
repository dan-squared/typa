import Testing
@testable import Typer

struct PracticeContentLibraryTests {
    @Test
    func diversifiedTestWordsFallsBackWhenInputIsEmpty() {
        #expect(
            PracticeContentLibrary.diversifiedTestWords(from: [], count: 5)
                == PracticeContentLibrary.fallbackWords
        )
    }

    @Test
    func diversifiedTestWordsReturnsUniqueOrderedWordsWhenCountIsZero() {
        let words = PracticeContentLibrary.diversifiedTestWords(
            from: ["alpha", "", "beta", "alpha", "gamma", "beta"],
            count: 0
        )

        #expect(words == ["alpha", "beta", "gamma"])
    }

    @Test
    func diversifiedTestWordsRepeatsSingleWordToRequestedCount() {
        let words = PracticeContentLibrary.diversifiedTestWords(
            from: ["swift", "swift"],
            count: 4
        )

        #expect(words == ["swift", "swift", "swift", "swift"])
    }
}
