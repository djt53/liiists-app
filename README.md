# liiists

A dead-simple list app where markdown files are the source of truth. Every interface -iOS app, CLI, AI tools -reads and writes the same files.

## Why

List apps are either too simple or too complex. None are designed to work with AI. liiists is markdown-first: any tool that can read a text file can work with your lists.

## What's built

**iOS app** -clean, native SwiftUI list app, [live on the App Store](https://apps.apple.com/app/id6761671906). Create lists, check items off, search across everything. Syncs via iCloud Drive.

**CLI** -manage lists from your terminal. Written in Go, zero dependencies.

```bash
liiists init                       # set up your lists directory
liiists new "Books to Read"        # create a list
liiists add books "Project Hail Mary"  # add an item
liiists ls                         # show all lists
liiists ls books                   # show items in a list
liiists check books "Project Hail Mary"  # toggle a checkbox
liiists rm books "Project Hail Mary"     # remove an item
echo "messy, text, input" | liiists parse books  # parse text into items
```

**MCP server** -lets AI assistants manage your lists programmatically. 8 tools: `list_lists`, `read_list`, `create_list`, `add_items`, `remove_item`, `check_item`, `delete_list`, `parse_text`.

```json
{
  "mcpServers": {
    "liiists": {
      "command": "node",
      "args": ["/path/to/liiists/mcp/index.js"]
    }
  }
}
```

**Agent skill** -[`SKILL.md`](./SKILL.md) is a drop-in skill file for Claude Code (and any coding agent that reads agent guides). Copy it into your skills directory (e.g. `~/.claude/skills/liiists/SKILL.md`) and your agent will know how to manage your lists via the CLI — adding items, parsing free-text dumps, checking things off. Works alongside the MCP server or on its own.

**Share Extension** -share a URL or text from any app into a list.

**Siri Shortcuts** -"Add Severance to my TV list."

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

- `type` is `list` (plain bullets) or `checklist` (checkboxes)
- Frontmatter is optional -a bare bullet list is a valid list
- Title resolves from: frontmatter > H1 heading > filename

## Architecture

```
liiists/
├── cli/              # Go CLI -single binary, fast
├── mcp/              # Node.js MCP server
├── liiists/          # SwiftUI iOS app
│   ├── Models/       # ItemList, ListItem
│   ├── Services/     # MarkdownParser, ListStore, iCloud sync
│   └── Views/        # HomeView, ListView
├── ShareExtension/   # iOS Share Sheet
└── liiistsTests/     # Markdown parser tests
```

All three interfaces share one contract: the markdown file format. No shared code, no shared runtime. Just files.

## Sync

The iOS app stores lists in an iCloud Drive container. Files are visible in Files.app and sync across devices. The CLI can read the same files at:

```
~/Library/Mobile Documents/iCloud~com~davidtingle~liiists/Documents/
```

Or point it at any directory via `~/.config/liiists/config.yaml`:

```yaml
lists_dir: ~/my-lists
```

## Design

The app's visual language is inspired by Nothing's design system, implemented using [dominikmartn/nothing-design-skill](https://github.com/dominikmartn/nothing-design-skill). Monochromatic, dark-first, with dot-matrix typography (Doto) and Space Grotesk/Space Mono.

## License

MIT
