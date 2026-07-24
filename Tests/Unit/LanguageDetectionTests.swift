import Testing
import NaturalLanguage
@testable import ClipboardVocab

@Suite("LanguageDetection Tests")
struct LanguageDetectionTests {

    private let service = LanguageDetectionService()

    @Test("Clearly English text is detected as English above threshold")
    func testClearlyEnglishTextReturnsEnglishAboveThreshold() {
        let result = service.detect(text: "The quick brown fox jumps over the lazy dog")
        #expect(result != nil)
        #expect(result?.language == .english)
        let confidence = result?.confidence ?? 0
        #expect(confidence >= LanguageDetectionService.confidenceThreshold)
    }

    @Test("isEnglish returns true for English word")
    func testIsEnglishReturnsTrueForEnglish() {
        #expect(service.isEnglish("threshold") == true)
    }

    @Test("French text is detected as French")
    func testClearlyFrenchTextReturnsFrench() {
        let result = service.detect(text: "bonjour le monde, comment allez-vous aujourd'hui")
        #expect(result != nil)
        #expect(result?.language == .french)
    }

    @Test("isEnglish returns false for French text")
    func testIsEnglishReturnsFalseForFrench() {
        #expect(service.isEnglish("bonjour le monde, comment allez-vous") == false)
    }

    @Test("Short ambiguous string does not produce high-confidence result")
    func testShortAmbiguousStringBehavior() {
        // A single accented character should not be detected as English
        #expect(service.isEnglish("à") == false)
    }

    @Test("Short English phrase is above confidence threshold")
    func testShortEnglishPhraseAboveThreshold() {
        // Use a short multi-word English phrase that NLLanguageRecognizer reliably classifies
        let result = service.detect(text: "good morning")
        #expect(result != nil)
        if let result {
            #expect(result.language == .english)
            #expect(result.confidence >= LanguageDetectionService.confidenceThreshold)
        }
    }
}
