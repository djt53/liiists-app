import Foundation

/// Represents a single liiists list backed by a markdown file.
struct ItemList: Identifiable, Equatable {
    let id: UUID
    var filename: String
    var title: String
    var type: ListType
    var createdDate: Date?
    var items: [ListItem]

    /// Extra frontmatter keys we don't recognize — preserved on round-trip.
    var extraFrontmatter: [String: String]

    enum ListType: String, Equatable {
        case list
        case checklist
    }

    init(
        id: UUID = UUID(),
        filename: String,
        title: String? = nil,
        type: ListType = .list,
        createdDate: Date? = nil,
        items: [ListItem] = [],
        extraFrontmatter: [String: String] = [:]
    ) {
        self.id = id
        self.filename = filename
        self.title = title ?? Self.titleFromFilename(filename)
        self.type = type
        self.createdDate = createdDate
        self.items = items
        self.extraFrontmatter = extraFrontmatter
    }

    var itemCount: Int { items.count }
    var checkedCount: Int { items.filter(\.isChecked).count }

    /// Convert a slug filename to a display title.
    /// "books-to-read.md" → "Books to Read"
    static func titleFromFilename(_ filename: String) -> String {
        filename
            .replacingOccurrences(of: ".md", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    /// Convert a display title to a slug filename.
    /// "Books to Read" → "books-to-read.md"
    static func filenameFromTitle(_ title: String) -> String {
        let slug = title
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return slug + ".md"
    }
}
