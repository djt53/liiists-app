import Foundation

/// Parses and writes liiists markdown files per the v1 spec.
///
/// Format:
/// ```
/// ---                          (optional frontmatter)
/// title: My List
/// type: checklist
/// created: 2026-03-26
/// ---
/// # Optional H1 Title
///
/// - [ ] Item one              (checklist)
/// - Item two                  (plain list)
/// ```
enum MarkdownParser {

    private static let iso8601Formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    // MARK: - Parse

    static func parse(content: String, filename: String) -> ItemList {
        let lines = content.components(separatedBy: .newlines)
        var index = 0

        // Parse optional frontmatter
        var frontmatter: [String: String] = [:]
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---" {
            index = 1
            while index < lines.count {
                let line = lines[index]
                index += 1
                if line.trimmingCharacters(in: .whitespaces) == "---" { break }
                if let colonRange = line.range(of: ":") {
                    let key = line[line.startIndex..<colonRange.lowerBound]
                        .trimmingCharacters(in: .whitespaces)
                    let value = line[colonRange.upperBound...]
                        .trimmingCharacters(in: .whitespaces)
                    frontmatter[key] = value
                }
            }
        }

        // Extract known fields
        let typeStr = frontmatter.removeValue(forKey: "type") ?? "list"
        let listType: ItemList.ListType
        switch typeStr {
        case "checklist": listType = .checklist
        case "streak": listType = .streak
        default: listType = .list
        }
        let titleFromFM = frontmatter.removeValue(forKey: "title")
        let createdStr = frontmatter.removeValue(forKey: "created")
        let createdDate = createdStr.flatMap { iso8601Formatter.date(from: $0) }

        // Scan for H1 title and items (or streak sections)
        var h1Title: String?
        var items: [ListItem] = []
        var streakSections: [StreakSection] = []

        if listType == .streak {
            // Streak parsing: H2 headings as sections, cadence lines, date entries
            var currentSection: StreakSection?

            while index < lines.count {
                let line = lines[index]
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                index += 1

                // H1 heading (title)
                if trimmed.hasPrefix("# ") && !trimmed.hasPrefix("## ") && h1Title == nil {
                    h1Title = String(trimmed.dropFirst(2))
                    continue
                }

                // H2 heading → new streak section
                if trimmed.hasPrefix("## ") {
                    if let section = currentSection {
                        streakSections.append(section)
                    }
                    currentSection = StreakSection(name: String(trimmed.dropFirst(3)))
                    continue
                }

                // Cadence line (immediately after H2)
                if trimmed.hasPrefix("cadence:"), currentSection != nil {
                    let value = String(trimmed.dropFirst(8)).trimmingCharacters(in: .whitespaces)
                    currentSection?.cadence = StreakCadence.from(value)
                    continue
                }

                // Date entry: - YYYY-MM-DD
                if trimmed.hasPrefix("- "), currentSection != nil {
                    let dateStr = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                    if let date = iso8601Formatter.date(from: dateStr) {
                        currentSection?.entries.append(date)
                    }
                    continue
                }
            }

            // Don't forget the last section
            if let section = currentSection {
                streakSections.append(section)
            }
        } else {
            // Standard list/checklist parsing
            while index < lines.count {
                let line = lines[index]
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                index += 1

                // H1 heading
                if trimmed.hasPrefix("# ") && h1Title == nil {
                    h1Title = String(trimmed.dropFirst(2))
                    continue
                }

                // Checklist item: - [ ] or - [x]
                if let item = parseChecklistItem(trimmed) {
                    items.append(item)
                    continue
                }

                // Plain bullet item: - text
                if let item = parseBulletItem(trimmed) {
                    items.append(item)
                    continue
                }
            }
        }

        // Title resolution: frontmatter > H1 > filename
        let title = titleFromFM ?? h1Title ?? ItemList.titleFromFilename(filename)

        return ItemList(
            filename: filename,
            title: title,
            type: listType,
            createdDate: createdDate,
            items: items,
            streakSections: streakSections,
            extraFrontmatter: frontmatter
        )
    }

    private static func parseChecklistItem(_ line: String) -> ListItem? {
        if line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ") {
            return ListItem(text: String(line.dropFirst(6)), isChecked: true)
        }
        if line.hasPrefix("- [ ] ") {
            return ListItem(text: String(line.dropFirst(6)), isChecked: false)
        }
        return nil
    }

    private static func parseBulletItem(_ line: String) -> ListItem? {
        guard line.hasPrefix("- ") else { return nil }
        let text = String(line.dropFirst(2))
        guard !text.isEmpty else { return nil }
        return ListItem(text: text)
    }

    // MARK: - Write

    static func write(_ list: ItemList) -> String {
        var lines: [String] = []

        // Frontmatter (only if there's something to write)
        var fm: [String: String] = list.extraFrontmatter
        fm["title"] = list.title
        fm["type"] = list.type.rawValue
        if let date = list.createdDate {
            fm["created"] = iso8601Formatter.string(from: date)
        }

        if !fm.isEmpty {
            lines.append("---")
            // Write known keys in a consistent order, then extras
            let orderedKeys = ["title", "type", "created"]
            for key in orderedKeys {
                if let value = fm.removeValue(forKey: key) {
                    lines.append("\(key): \(value)")
                }
            }
            for (key, value) in fm.sorted(by: { $0.key < $1.key }) {
                lines.append("\(key): \(value)")
            }
            lines.append("---")
            lines.append("")
        }

        // Items / sections
        switch list.type {
        case .streak:
            for (i, section) in list.streakSections.enumerated() {
                if i > 0 { lines.append("") }
                lines.append("## \(section.name)")
                lines.append("cadence: \(section.cadence.markdownString)")
                lines.append("")
                for date in section.entries {
                    lines.append("- \(iso8601Formatter.string(from: date))")
                }
            }
        case .checklist:
            for item in list.items {
                let check = item.isChecked ? "x" : " "
                lines.append("- [\(check)] \(item.text)")
            }
        case .list:
            for item in list.items {
                lines.append("- \(item.text)")
            }
        }

        // Trailing newline
        lines.append("")
        return lines.joined(separator: "\n")
    }
}
