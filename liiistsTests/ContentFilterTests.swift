import XCTest
@testable import liiists

final class ContentFilterTests: XCTestCase {

    func testCleanTextPasses() {
        XCTAssertTrue(ContentFilter.isClean("Books to Read"))
        XCTAssertTrue(ContentFilter.isClean("Coffee shops near me"))
        XCTAssertTrue(ContentFilter.isClean(""))
    }

    func testRawSlurBlocked() {
        XCTAssertEqual(ContentFilter.firstMatch("fuck this"), "fuck")
        XCTAssertEqual(ContentFilter.firstMatch("FUCK THIS"), "fuck")
    }

    func testWordBoundaryPreventsSubstringFalsePositives() {
        XCTAssertTrue(ContentFilter.isClean("Scunthorpe"))
        XCTAssertTrue(ContentFilter.isClean("specific"))
        XCTAssertTrue(ContentFilter.isClean("Saskatchewan"))
        XCTAssertTrue(ContentFilter.isClean("dickens"))
        XCTAssertTrue(ContentFilter.isClean("class"))
    }

    func testDiacriticObfuscationCaught() {
        XCTAssertEqual(ContentFilter.firstMatch("Fück this"), "fuck")
        XCTAssertEqual(ContentFilter.firstMatch("Nïgger"), "nigger")
        XCTAssertEqual(ContentFilter.firstMatch("pörn"), "porn")
    }

    func testFullWidthObfuscationCaught() {
        XCTAssertEqual(ContentFilter.firstMatch("ｆｕｃｋ"), "fuck")
    }

    func testLeetspeakAndSpacingNotCaughtByDesign() {
        // Documenting the tradeoff: catching these would require substring
        // matching, which false-positives on innocuous words. Falls through
        // to Report + ejection.
        XCTAssertTrue(ContentFilter.isClean("n1gger"))
        XCTAssertTrue(ContentFilter.isClean("f u c k"))
    }

    func testFirstMatchInListChecksTitleAndItems() {
        XCTAssertNil(ContentFilter.firstMatchInList(title: "Reading", items: ["Dune", "Neuromancer"]))
        XCTAssertEqual(
            ContentFilter.firstMatchInList(title: "Fück list", items: ["clean"]),
            "fuck"
        )
        XCTAssertEqual(
            ContentFilter.firstMatchInList(title: "Reading", items: ["clean", "this is shit"]),
            "shit"
        )
    }
}
