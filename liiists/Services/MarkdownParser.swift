import Foundation

/// Parses and writes liiists markdown files per the v1 spec.
///
/// Format:
/// ```
/// ---                          (optional frontmatter)
/// title: My List
/// type: checklist              (or list, or streak)
/// created: 2026-03-26
/// cadence: daily               (only for streak)
/// ---
/// # Optional H1 Title
///
/// - [ ] Item one              (checklist)
/// - Item two                  (plain list)
/// - 2026-05-03                (streak — one ISO date per entry)
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
        let cadenceStr = frontmatter.removeValue(forKey: "cadence")
        let streakCadence: StreakCadence? = listType == .streak
            ? StreakCadence.from(cadenceStr ?? "daily")
            : nil

        // Scan for H1 title and items
        var h1Title: String?
        var items: [ListItem] = []
        var streakEntries: [Date] = []

        if listType == .streak {
            // Streak parsing: any `- YYYY-MM-DD` bullet is an entry.
            // H2 headings and `cadence:` body lines from the legacy
            // multi-section format are ignored.
            while index < lines.count {
                let line = lines[index]
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                index += 1

                if trimmed.hasPrefix("# ") && !trimmed.hasPrefix("## ") && h1Title == nil {
                    h1Title = String(trimmed.dropFirst(2))
                    continue
                }

                if trimmed.hasPrefix("- ") {
                    let dateStr = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                    if let date = iso8601Formatter.date(from: dateStr) {
                        streakEntries.append(date)
                    }
                }
            }
            streakEntries.sort(by: >)
        } else {
            // Standard list/checklist parsing
            while index < lines.count {
                let line = lines[index]
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                index += 1

                if trimmed.hasPrefix("# ") && h1Title == nil {
                    h1Title = String(trimmed.dropFirst(2))
                    continue
                }

                if let item = parseChecklistItem(trimmed) {
                    items.append(item)
                    continue
                }

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
            streakCadence: streakCadence,
            streakEntries: streakEntries,
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

        // Frontmatter
        var fm: [String: String] = list.extraFrontmatter
        fm["title"] = list.title
        fm["type"] = list.type.rawValue
        if let date = list.createdDate {
            fm["created"] = iso8601Formatter.string(from: date)
        }
        if list.type == .streak, let cadence = list.streakCadence {
            fm["cadence"] = cadence.markdownString
        }

        if !fm.isEmpty {
            lines.append("---")
            let orderedKeys = ["title", "type", "created", "cadence"]
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

        // Body
        switch list.type {
        case .streak:
            for date in list.streakEntries.sorted(by: >) {
                lines.append("- \(iso8601Formatter.string(from: date))")
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
