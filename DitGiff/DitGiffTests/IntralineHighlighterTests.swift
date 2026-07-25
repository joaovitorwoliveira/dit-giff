import Testing

@testable import DitGiff

nonisolated struct IntralineHighlighterTests {

    @Test func highlightsChangeInTheMiddle() {
        let result = IntralineHighlighter.highlight(
            deletion: "hello world",
            addition: "hello there"
        )

        #expect(result.deletion == [
            PatchLineSegment(text: "hello ", isHighlighted: false),
            PatchLineSegment(text: "world", isHighlighted: true),
        ])
        #expect(result.addition == [
            PatchLineSegment(text: "hello ", isHighlighted: false),
            PatchLineSegment(text: "there", isHighlighted: true),
        ])
    }

    @Test func highlightsChangeAtTheStart() {
        let result = IntralineHighlighter.highlight(
            deletion: "foo bar",
            addition: "baz bar"
        )

        #expect(result.deletion == [
            PatchLineSegment(text: "foo", isHighlighted: true),
            PatchLineSegment(text: " bar", isHighlighted: false),
        ])
        #expect(result.addition == [
            PatchLineSegment(text: "baz", isHighlighted: true),
            PatchLineSegment(text: " bar", isHighlighted: false),
        ])
    }

    @Test func highlightsChangeAtTheEnd() {
        let result = IntralineHighlighter.highlight(
            deletion: "prefix old",
            addition: "prefix new"
        )

        #expect(result.deletion == [
            PatchLineSegment(text: "prefix ", isHighlighted: false),
            PatchLineSegment(text: "old", isHighlighted: true),
        ])
        #expect(result.addition == [
            PatchLineSegment(text: "prefix ", isHighlighted: false),
            PatchLineSegment(text: "new", isHighlighted: true),
        ])
    }

    @Test func wholeLineHighlightedWhenNothingInCommon() {
        // Chosen so prefix and suffix share no Character — "alpha"/"omega" share a trailing "a".
        let result = IntralineHighlighter.highlight(
            deletion: "xyz",
            addition: "123"
        )

        #expect(result.deletion == [
            PatchLineSegment(text: "xyz", isHighlighted: true),
        ])
        #expect(result.addition == [
            PatchLineSegment(text: "123", isHighlighted: true),
        ])
    }

    @Test func worksWithAccentAndEmojiOnCharacterBoundaries() {
        let result = IntralineHighlighter.highlight(
            deletion: "café 👋 mundo",
            addition: "café 🎉 mundo"
        )

        #expect(result.deletion == [
            PatchLineSegment(text: "café ", isHighlighted: false),
            PatchLineSegment(text: "👋", isHighlighted: true),
            PatchLineSegment(text: " mundo", isHighlighted: false),
        ])
        #expect(result.addition == [
            PatchLineSegment(text: "café ", isHighlighted: false),
            PatchLineSegment(text: "🎉", isHighlighted: true),
            PatchLineSegment(text: " mundo", isHighlighted: false),
        ])
    }

    @Test func identicalLinesProduceNoHighlight() {
        let result = IntralineHighlighter.highlight(
            deletion: "same",
            addition: "same"
        )

        #expect(result.deletion == [
            PatchLineSegment(text: "same", isHighlighted: false),
        ])
        #expect(result.addition == [
            PatchLineSegment(text: "same", isHighlighted: false),
        ])
    }

    @Test func emptyLinesProduceSingleEmptySegment() {
        let result = IntralineHighlighter.highlight(deletion: "", addition: "")

        #expect(result.deletion == [
            PatchLineSegment(text: "", isHighlighted: false),
        ])
        #expect(result.addition == [
            PatchLineSegment(text: "", isHighlighted: false),
        ])
    }

    @Test func extendingSharedRunDoesNotOverlapPrefixAndSuffix() {
        let aaVersusAaa = IntralineHighlighter.highlight(deletion: "aa", addition: "aaa")
        #expect(aaVersusAaa.deletion == [
            PatchLineSegment(text: "aa", isHighlighted: false),
        ])
        #expect(aaVersusAaa.addition == [
            PatchLineSegment(text: "aa", isHighlighted: false),
            PatchLineSegment(text: "a", isHighlighted: true),
        ])

        let abaVersusAbba = IntralineHighlighter.highlight(deletion: "aba", addition: "abba")
        #expect(abaVersusAbba.deletion == [
            PatchLineSegment(text: "ab", isHighlighted: false),
            PatchLineSegment(text: "a", isHighlighted: false),
        ])
        #expect(abaVersusAbba.addition == [
            PatchLineSegment(text: "ab", isHighlighted: false),
            PatchLineSegment(text: "b", isHighlighted: true),
            PatchLineSegment(text: "a", isHighlighted: false),
        ])
    }

    @Test func composedAndDecomposedAccentAreEqualCharacters() {
        let composed = "caf\u{00E9}" // é as a single code point
        let decomposed = "cafe\u{0301}" // e + combining acute
        #expect(composed == decomposed)

        let result = IntralineHighlighter.highlight(deletion: composed, addition: decomposed)
        #expect(result.deletion == [
            PatchLineSegment(text: composed, isHighlighted: false),
        ])
        #expect(result.addition == [
            PatchLineSegment(text: decomposed, isHighlighted: false),
        ])
        #expect(result.deletion.allSatisfy { !$0.isHighlighted })
        #expect(result.addition.allSatisfy { !$0.isHighlighted })
    }

    @Test func zeroWidthJoinerFamilyEmojiComparedAsCharacters() {
        let familyOfThree = "👨\u{200D}👩\u{200D}👧"
        let familyOfFour = "👨\u{200D}👩\u{200D}👧\u{200D}👦"
        #expect(Array(familyOfThree).count == 1)
        #expect(Array(familyOfFour).count == 1)

        let result = IntralineHighlighter.highlight(
            deletion: familyOfThree,
            addition: familyOfFour
        )

        #expect(result.deletion == [
            PatchLineSegment(text: familyOfThree, isHighlighted: true),
        ])
        #expect(result.addition == [
            PatchLineSegment(text: familyOfFour, isHighlighted: true),
        ])
    }

    @Test func pairedIdenticalLinesProduceNoHighlight() {
        let result = IntralineHighlighter.highlight(
            deletion: "unchanged pair",
            addition: "unchanged pair"
        )

        #expect(result.deletion == [
            PatchLineSegment(text: "unchanged pair", isHighlighted: false),
        ])
        #expect(result.addition == [
            PatchLineSegment(text: "unchanged pair", isHighlighted: false),
        ])
    }
}
