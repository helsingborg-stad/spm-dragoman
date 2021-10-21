import XCTest
import Combine
import TextTranslator
@testable import Dragoman


var cancellables = Set<AnyCancellable>()

let firstTest = "test string 3"
let firstTestTranslated = "test string 3 has been translated"

let secondTest = "test string 4"
let secondTestTranslated = "test string 4 has been translated"

class TestTextTranslator : TextTranslationService {
    var translationDict = [String:String]()
    init() {
        translationDict[firstTest] = firstTestTranslated
        translationDict[secondTest] = secondTestTranslated
    }
    func translate(_ texts: [TranslationKey : String], from: LanguageKey, to: [LanguageKey], storeIn table: TextTransaltionTable) -> FinishedPublisher {
        let subj = FinishedSubject()
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 1) {
            var table = table
            for (key,_) in texts {
                for l in to {
                    if table.db[l] == nil {
                        table.db[l] = [:]
                    }
                    if let val = self.translationDict[key] {
                        table[l,key] = val
                    } else {
                        table[l,key] = "unknown key \(key)"
                    }
                }
            }
            subj.send(table)
        }
        return subj.eraseToAnyPublisher()
    }
    
    func translate(_ texts: [String], from: LanguageKey, to: [LanguageKey], storeIn table: TextTransaltionTable) -> FinishedPublisher {
        let subj = FinishedSubject()
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 1) {
            var table = table
            for key in texts {
                for l in to {
                    if let val = self.translationDict[key] {
                        table[l,key] = val
                    } else {
                        table[l,key] = "unknown key \(key)"
                    }
                }
            }
            subj.send(table)
        }
        return subj.eraseToAnyPublisher()
    }
    
    func translate(_ text: String, from: LanguageKey, to: LanguageKey) -> TranslatedPublisher {
        let subj = TranslatedSubject()
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 1) {
            subj.send(TranslatedString(language: to, key: text, value: "mock translation"))
        }
        return subj.eraseToAnyPublisher()
    }
}

final class DragomanTests: XCTestCase {
    func testDragoman() {
        let expectation = XCTestExpectation(description: "testDragoman")
        let dragoman = Dragoman(locale: Locale(identifier: "se-SV"), supportedLanguages: ["se","en"])
        dragoman.translationService = TestTextTranslator()
        dragoman.clean()
        dragoman.translate([firstTest], from: "sv", to: ["en"]).sink { compl in
            if case let .failure(error) = compl {
                debugPrint(error)
                XCTFail(error.localizedDescription)
            }
        } receiveValue: {
            XCTAssert(dragoman.string(forKey: firstTest, in: "en") == firstTestTranslated)
            dragoman.locale = Locale(identifier: "en-US")
            dragoman.translate([secondTest], from: "sv", to: ["en"]).sink { compl in
                if case let .failure(error) = compl {
                    debugPrint(error)
                    XCTFail(error.localizedDescription)
                }
            } receiveValue: {
                XCTAssert(dragoman.string(forKey: secondTest, in: "en") == secondTestTranslated)
                expectation.fulfill()
            }.store(in: &cancellables)
        }.store(in: &cancellables)
        wait(for: [expectation], timeout: 20)
    }
    func testDragoman2() {
        let dragoman = Dragoman(locale: Locale(identifier: "se-SV"), supportedLanguages: ["se","en"])
        dragoman.translationService = TestTextTranslator()
        XCTAssert(dragoman.string(forKey: firstTest, in: "en") == firstTestTranslated)
        XCTAssert(dragoman.string(forKey: secondTest, in: "en") == secondTestTranslated)
    }
}
