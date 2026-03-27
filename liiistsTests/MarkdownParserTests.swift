import XCTest
@testable import liiists

final class MarkdownParserTests: XCTestCase {

    func testParseMinimalFile() {
        let content = """
        - Dune
        - Neuromancer
        """
        let list = MarkdownParser.parse(content: content, filename: "books.md")
        XCTAssertEqual(list.title, "Books")
        XCTAssertEqual(list.type, .list)
        XCTAssertEqual(list.items.count, 2)
        XCTAssertEqual(list.items[0].text, "Dune")
        XCTAssertEqual(list.items[1].text, "Neuromancer")
    }

    func testParseWithFrontmatter() {
        let content = """
        ---
        title: Books to Read
        type: checklist
        created: 2026-03-26
        ---
        - [x] Dune
        - [ ] Neuromancer
        """
        let list = MarkdownParser.parse(content: content, filename: "books.md")
        XCTAssertEqual(list.title, "Books to Read")
        XCTAssertEqual(list.type, .checklist)
        XCTAssertNotNil(list.createdDate)
        XCTAssertEqual(list.items.count, 2)
        XCTAssertTrue(list.items[0].isChecked)
        XCTAssertFalse(list.items[1].isChecked)
    }

    func testParseWithH1Title() {
        let content = """
        # My Favorite Books

        - Dune
        - Neuromancer
        """
        let list = MarkdownParser.parse(content: content, filename: "books.md")
        XCTAssertEqual(list.title, "My Favorite Books")
    }

    func testTitleResolutionPriority() {
        // Frontmatter title wins over H1
        let content = """
        ---
        title: FM Title
        ---
        # H1 Title

        - Item
        """
        let list = MarkdownParser.parse(content: content, filename: "fallback.md")
        XCTAssertEqual(list.title, "FM Title")
    }

    func testTitleFromFilename() {
        XCTAssertEqual(ItemList.titleFromFilename("books-to-read.md"), "Books To Read")
        XCTAssertEqual(ItemList.titleFromFilename("movies.md"), "Movies")
    }

    func testFilenameFromTitle() {
        XCTAssertEqual(ItemList.filenameFromTitle("Books to Read"), "books-to-read.md")
        XCTAssertEqual(ItemList.filenameFromTitle("Movies"), "movies.md")
    }

    func testRoundTrip() {
        let original = ItemList(
            filename: "test.md",
            title: "Test List",
            type: .checklist,
            createdDate: Date(),
            items: [
                ListItem(text: "Item A", isChecked: true),
                ListItem(text: "Item B", isChecked: false),
            ]
        )
        let markdown = MarkdownParser.write(original)
        let parsed = MarkdownParser.parse(content: markdown, filename: "test.md")

        XCTAssertEqual(parsed.title, original.title)
        XCTAssertEqual(parsed.type, original.type)
        XCTAssertEqual(parsed.items.count, original.items.count)
        XCTAssertEqual(parsed.items[0].text, "Item A")
        XCTAssertTrue(parsed.items[0].isChecked)
        XCTAssertEqual(parsed.items[1].text, "Item B")
        XCTAssertFalse(parsed.items[1].isChecked)
    }

    func testExtraFrontmatterPreserved() {
        let content = """
        ---
        title: Test
        custom_field: hello
        ---
        - Item
        """
        let list = MarkdownParser.parse(content: content, filename: "test.md")
        XCTAssertEqual(list.extraFrontmatter["custom_field"], "hello")

        let output = MarkdownParser.write(list)
        XCTAssertTrue(output.contains("custom_field: hello"))
    }
}
