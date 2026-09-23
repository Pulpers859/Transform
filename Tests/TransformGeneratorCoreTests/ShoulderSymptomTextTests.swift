import XCTest
@testable import Transform

final class ShoulderSymptomTextTests: XCTestCase {
    func testOnlyCompleteUnambiguousClausesAreRewritten() {
        for item in ShoulderSymptomTextCases.examples {
            XCTAssertEqual(ShoulderSymptomText.movementMatchingText(item.input,
                movementPhrases: ShoulderSymptomTextCases.phrases), item.expected, item.input)
        }
    }
}
