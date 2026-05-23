# liiists (iOS)

The iOS app for [liiists](https://github.com/djt53/liiists) — one list app that works from the terminal, on iOS, and through any AI agent, all reading the same markdown files.

[Live on the App Store](https://apps.apple.com/app/id6761671906).

The CLI, MCP server, and `SKILL.md` live in a separate repo: [djt53/liiists](https://github.com/djt53/liiists).

## What's in this repo

Native SwiftUI app, iOS 18+. Reads and writes `.md` files in an iCloud Drive container (or any folder you point it at via the document picker). Features:

- **Lists and checklists** — markdown-backed, no proprietary format
- **Logs** — timestamped reverse-chronological entries for media journals, food diaries, workouts, anything where *when* matters. Searchable by text or date (`"yesterday"`, `"may 14"`). Per-list option to hide the time column for a quieter visual.
- **iCloud Drive sync** — your lists live in `Mobile Documents/iCloud~com~davidtingle~liiists/Documents/`, visible in Files.app
- **Share Extension** — share a URL or text from any app into a chosen list
- **Siri Shortcuts** — *"Hey Siri, add Severance to my TV list"*
- **Widgets** — single list, all lists, or quick-add from the home screen
- **On-device AI "Suggest more"** — Apple Foundation Models proposes new items based on what's already on the list. Runs locally; no server call.
- **Discover** — optionally publish a list publicly. Other users can browse, upvote, save, and copy lists into their own collection. Anonymous-first; no account needed unless you want to publish.

## The format

Lists are plain markdown files. That's it.

```markdown
---
title: Books to Read
type: checklist
created: 2026-03-26
---

- [x] Project Hail Mary
- [ ] Tomorrow, and Tomorrow, and Tomorrow
- [ ] The Kaiju Preservation Society
```

Logs use a timestamped bullet format — naive local datetime (no timezone) joined to text with an em-dash:

```markdown
---
title: Media Log
type: log
created: 2026-05-23
---

- 2026-05-23T22:55 — Sirat #film
- 2026-05-22T19:30 — Severance S2E10
```

- `type` is `list` (plain bullets), `checklist` (checkboxes), or `log` (timestamped entries)
- Frontmatter is optional — a bare bullet list is a valid list
- Title resolves from: frontmatter > H1 heading > filename

Same format the CLI and MCP server read and write. Edit a list from any of the three surfaces and the others see it next sync. (CLI/MCP support for log lists is planned; today they round-trip log files as plain text without timestamp-awareness.)

## Structure

```
liiists-app/
├── liiists/             # SwiftUI app target
│   ├── Models/          # ItemList, ListItem
│   ├── Services/        # MarkdownParser, ListStore, PublishStore, IntelligenceStore
│   └── Views/           # HomeView, ListView, DiscoverView
├── ShareExtension/      # iOS Share Sheet target
├── LiiistsWidget/       # WidgetKit target
├── liiistsTests/        # Markdown parser tests
└── project.yml          # xcodegen project definition
```

CloudKit (Discover only) and StoreKit 2 (Pro tier, currently dormant) are the only external dependencies; everything else runs against Apple frameworks.

## Design

The visual language is inspired by Nothing's design system, implemented using [dominikmartn/nothing-design-skill](https://github.com/dominikmartn/nothing-design-skill). Monochromatic, dark-first, dot-matrix typography (Doto) paired with Space Grotesk and Space Mono.

## License

MIT
