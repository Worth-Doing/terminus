<p align="center">
  <img src="https://raw.githubusercontent.com/Worth-Doing/brand-assets/main/png/variants/04-horizontal.png" alt="WorthDoing.ai" width="600" />
</p>

<p align="center">
  <img src="Resources/AppIcon.svg" alt="Terminus" width="128" />
</p>

<h1 align="center">Terminus</h1>

<p align="center">
  <strong>The intelligent terminal for the post-LLM era.</strong>
</p>

<p align="center">
  A next-generation macOS terminal built in Swift + SwiftUI.<br/>
  Zero dependencies. Native performance. AI-powered command intelligence.
</p>

<p align="center">
  <a href="https://github.com/Worth-Doing/terminus/releases/latest/download/Terminus-0.3.0.dmg">
    <img src="https://img.shields.io/badge/Download-Terminus%200.3.0%20DMG-blue?style=for-the-badge&logo=apple" alt="Download Terminus DMG" />
  </a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014+-black?style=flat-square&logo=apple" />
  <img src="https://img.shields.io/badge/swift-6.0-orange?style=flat-square&logo=swift" />
  <img src="https://img.shields.io/badge/dependencies-0-green?style=flat-square" />
  <img src="https://img.shields.io/badge/notarized-Apple-blue?style=flat-square&logo=apple" />
  <img src="https://img.shields.io/badge/license-MIT-lightgrey?style=flat-square" />
</p>

---

## Download

**[Download Terminus-0.3.0.dmg](https://github.com/Worth-Doing/terminus/releases/latest/download/Terminus-0.3.0.dmg)** (~4 MB)

> Signed and notarized by Apple. Runs on macOS 14+ (Sonoma and later), Apple Silicon & Intel.
>
> Open the DMG and drag `Terminus.app` to Applications.

---

## What is Terminus?

Terminus is a **native macOS terminal** that combines traditional shell power with intelligent command assistance:

- **Real terminal emulator** — VT100/xterm compatible, true color, alternate screen buffer
- **Natural language commands** — Type "find large files here" and get executable shell commands via AI
- **Multi-panel workspace** — Split horizontally/vertically, tabs, spatial keyboard navigation
- **Learning-based predictions** — Learns your command patterns, suggests based on frequency, recency, directory, and project context
- **Command safety analysis** — Detects destructive commands before execution, warns about risks
- **Command blocks** — Structured output with collapsible blocks, re-run, copy actions
- **File explorer** — Built-in directory browser with file preview and breadcrumb navigation
- **Command history** — Searchable, filterable, with favorites and edit-and-rerun
- **Workflow automation** — Save multi-step command sequences, run with progress tracking
- **Output visualization** — Smart rendering for JSON (collapsible tree), diffs (colored), errors (highlighted)
- **System monitor** — Live CPU, RAM, GPU, disk, and network metrics in a side panel
- **Semantic search** — Search command history by meaning, powered by OpenRouter embeddings
- **Command palette** — Fuzzy-searchable launcher for every action (`Cmd+Shift+P`)

The terminal works fully offline — AI is an optional enhancement that activates when you add an OpenRouter API key.

---

## Screenshots

### Terminal + AI Command Bar
```
┌──────────────────────────────────────────────────────────────────────────┐
│ [split] [split-v] [close]                    [AI] [cmd] [search] [...] │
├──────────────────────────────────────────────────────────────────────────┤
│ $ git status                                                            │
│ On branch main                                                          │
│ Changes not staged for commit:                                          │
│   modified:   src/app.ts                                                │
│                                                                         │
│ ┌─ AI Suggestion ──────────────────────────────────────────────────────┐│
│ │ $ find . -type f -size +100M                                        ││
│ │ Finds all files larger than 100MB in the current directory          ││
│ │ [Run]  [Edit]  [Copy]                            [Safe ✓]          ││
│ └─────────────────────────────────────────────────────────────────────┘│
│                                                                         │
│ ┌─────────────────────────────────────────────────────────────────────┐│
│ │ [sparkles AI]  Ask in natural language...         [Ask AI]  Enter  ││
│ └─────────────────────────────────────────────────────────────────────┘│
└──────────────────────────────────────────────────────────────────────────┘
```

---

## Features

### Natural Language Commands (New in v0.3.0)
- Type requests in plain English: "find all large files", "kill processes on port 3000"
- AI generates safe, correct shell commands with explanations
- Toggle between **AI mode** and **Command mode** with `Tab`
- Safety analysis: commands classified as safe/moderate/dangerous/critical
- Warning badges for destructive operations (`rm -rf`, `sudo`, etc.)
- Run, edit, copy, or reject AI-generated commands
- Session memory for context-aware follow-up requests
- Error recovery: AI suggests fixes when commands fail

### Command Intelligence (New in v0.3.0)
- Inline command explanations with part-by-part breakdown
- Flag explanations (`-rf`, `--force`, etc.)
- Risk level assessment for any command
- Improvement suggestions (performance, safety, readability)

### Command Blocks (New in v0.3.0)
- Each command execution becomes a structured block
- Blocks contain: input, output, metadata (time, duration, exit code)
- Collapse/expand, copy, re-run any block
- AI-generated commands displayed in distinct styled blocks
- Smart output rendering: JSON tree viewer, diff viewer, error highlighting

### File Explorer (New in v0.3.0)
- Built-in directory tree panel (`Cmd+Shift+E`)
- Breadcrumb navigation bar
- Language-specific file icons and colors
- Inline file preview for text files
- Double-click to `cd` into directories or insert file paths
- File size display

### Command History (New in v0.3.0)
- Full-text search across all command history (`Cmd+Y`)
- Filter by: all, successful, failed, favorites
- Pin favorite commands with star toggle
- Edit-and-rerun: modify a previous command before executing
- Time-ago display, directory context, duration metadata

### Workflow Automation (New in v0.3.0)
- Save multi-step command sequences as reusable workflows
- Step-by-step execution with progress tracking
- Continue-on-error flag per step
- Tag-based organization
- Create, edit, run, delete workflows

### Output Visualization (New in v0.3.0)
- **JSON Viewer** — Collapsible tree with syntax-colored keys/values and search
- **Diff Viewer** — Colored +/- lines with green/red backgrounds
- **Error Output** — Highlighted error keywords with "Fix with AI" button
- **Search within output** — Find text in command output with match navigation

### Terminal Core
- PTY via `forkpty()` with full process lifecycle management
- VT100/xterm escape sequence parser (CSI, SGR, OSC, DCS)
- 256-color and 24-bit true color support
- Alternate screen buffer (vim, less, htop)
- Scrollback buffer (configurable, default 10,000 lines)
- Mouse selection, copy/paste, word selection (double-click)
- Bracketed paste mode

### Multi-Panel Workspace
- Split horizontally (`Cmd+D`) or vertically (`Cmd+Shift+D`)
- Draggable dividers with minimum size enforcement
- Spatial focus navigation (`Cmd+Option+Arrow`)
- Multiple tabs with independent workspaces
- Double-click divider to reset 50/50

### Smart Predictions
- Multi-signal scoring: frequency, recency, prefix match, directory context, project type, n-gram sequences, feedback loop
- Project type detection via marker files (package.json, Cargo.toml, Package.swift, go.mod, etc.)
- Git branch awareness
- Works 100% offline — no AI required

### System Monitor (`Cmd+Shift+M`)
- Real-time CPU usage with per-core data and sparkline history
- RAM usage: active, wired, compressed, swap, pressure gauge
- GPU utilization via IOKit (Apple Silicon + discrete)
- Disk usage and network throughput (download/upload)
- Top 8 processes by memory consumption

### Saved Commands
- Save any command with a name, description, and tags
- Template parameters: `deploy {{environment}} --tag {{version}}`
- Tag-based filtering in sidebar
- Quick insert from command palette or sidebar

### AI Features (Optional, via OpenRouter)
- Natural language to shell command generation
- Command explanation and flag breakdown
- Error recovery suggestions
- Semantic search over command history using embeddings
- Safety analysis for all AI-generated commands
- API key stored in macOS Keychain
- Model browser with dynamic listing from OpenRouter
- Configurable: temperature, max tokens, safety level
- Models configurable (default: Claude Sonnet for chat, text-embedding-3-small for embeddings)

### Settings (Enhanced in v0.3.0)
- **AI tab**: Connection status, API key management (add/validate/remove), model browser, temperature/max tokens sliders, safety level configuration, AI feature toggles
- **Appearance**: 6 built-in themes (light & dark), font picker, cursor style, accent colors
- **Shortcuts**: Full reference with new AI and panel shortcuts

### Appearance & Theming
- 6 built-in themes with light & dark variants:
  - **Light:** Terminus Light (default), Solarized Light
  - **Dark:** Terminus Dark, Solarized Dark, Dracula, Nord
- Glass UI with material backgrounds and spring animations
- Font picker: SF Mono, Menlo, JetBrains Mono, Fira Code, and more
- Font size slider (10pt — 28pt)
- Cursor style: block, underline, bar (with blink)
- Accent color presets

---

## Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| **AI & Intelligence** | |
| AI Command Bar | `Cmd + L` |
| Toggle AI/Command Mode | `Tab` (in command bar) |
| Command Palette | `Cmd + Shift + P` |
| Semantic Search | `Cmd + Shift + F` |
| **Panels** | |
| Command History | `Cmd + Y` |
| File Explorer | `Cmd + Shift + E` |
| System Monitor | `Cmd + Shift + M` |
| Toggle Sidebar | `Cmd + B` |
| **Workspace** | |
| Split Horizontally | `Cmd + D` |
| Split Vertically | `Cmd + Shift + D` |
| Close Panel | `Cmd + W` |
| New Tab | `Cmd + T` |
| Focus Next Panel | `Cmd + Shift + ]` |
| Focus Previous Panel | `Cmd + Shift + [` |
| Focus Right/Left/Up/Down | `Cmd + Option + Arrow` |
| **Terminal** | |
| Copy | `Cmd + C` |
| Paste | `Cmd + V` |
| Select All | `Cmd + A` |
| Clear Terminal | `Cmd + K` |
| Settings | `Cmd + ,` |

---

## Architecture

**17 modules**, zero external dependencies. Everything uses system frameworks:

| Module | Purpose |
|--------|---------|
| `Terminus` | App entry point, main view, toolbar, tabs |
| `SharedModels` | All data types (terminal, AI, blocks, workflows) |
| `DataStore` | SQLite wrapper + schema |
| `SecureStorage` | Keychain wrapper |
| `SharedUI` | Theme system, design tokens, command palette |
| `TerminalCore` | PTY lifecycle (forkpty) |
| `TerminalEmulator` | VT100 parser + buffer + shell integration |
| `TerminalUI` | Rendering, NL bar, blocks, history, files, workflows, output viz |
| `WorkspaceEngine` | Panel tree + splits + tabs |
| `HistoryEngine` | Command history + n-gram tracking |
| `PredictionEngine` | Smart suggestions + project detection |
| `SavedCommands` | Saved command CRUD + UI |
| `AIService` | OpenRouter client, NL pipeline, safety analyzer, command intelligence |
| `EmbeddingPipeline` | Vector search (Accelerate/vDSP) |
| `SystemMonitor` | Live CPU/RAM/GPU/disk/network metrics |
| `OnboardingUI` | First-run flow |
| `SettingsUI` | Preferences with AI model browser |

### System Frameworks Used
`Foundation` `SwiftUI` `AppKit` `CoreText` `Security` `SQLite3` `Accelerate` `IOKit` `Darwin`

---

## Build from Source

```bash
# Requirements: macOS 14+, Swift 6.0+

# Clone
git clone https://github.com/Worth-Doing/terminus.git
cd terminus

# Build and run (development)
swift build
swift run Terminus

# Run tests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test

# Build unsigned .app bundle
./Scripts/bundle-app.sh

# Build signed .app bundle
./Scripts/bundle-app.sh --sign

# Build signed + Apple notarized
./Scripts/bundle-app.sh --notarize
```

---

## Project Stats

| Metric | Value |
|--------|-------|
| Swift files | 41 |
| Lines of code | ~14,000 |
| Modules | 17 |
| Themes | 6 (2 light, 4 dark) |
| External dependencies | 0 |
| Binary size | 6.0 MB |

---

## Roadmap

- [x] Mouse reporting (modes 1000, 1002, 1003)
- [x] Hyperlink support (OSC 8)
- [x] Glass UI redesign (iOS 26 aesthetic)
- [x] Full prediction engine (7-signal scoring)
- [x] N-gram command sequence learning
- [x] Performance optimization (dirty region tracking, render batching)
- [x] Natural language command generation (OpenRouter)
- [x] Command safety analysis (4 levels)
- [x] Block-based terminal output
- [x] File explorer panel
- [x] Advanced command history with search/filter/favorites
- [x] Workflow automation system
- [x] Output visualization (JSON tree, diff, error highlighting)
- [x] Command intelligence (explain, suggest improvements)
- [x] Error recovery with AI fix suggestions
- [ ] Ligatures support (Fira Code, JetBrains Mono)
- [ ] Sixel image protocol
- [ ] tmux integration
- [ ] Plugin system
- [ ] Custom theme editor / theme import
- [ ] iCloud sync for saved commands
- [ ] Session save/restore

---

## Changelog

### v0.3.0 — Next-Generation Intelligence (2025-04-15)
- Natural language command system with OpenRouter AI
- Command safety analyzer (safe/moderate/dangerous/critical)
- AI command bar with mode toggle (Tab to switch AI/Command)
- Command intelligence: inline explanations, flag breakdown, improvement suggestions
- Error recovery: AI-powered fix suggestions for failed commands
- Block-based terminal output with collapse/expand/copy/re-run
- File explorer panel with breadcrumbs, preview, language-colored icons
- Advanced command history panel with search, filter, favorites
- Workflow automation: multi-step command sequences with progress tracking
- Output visualization: JSON tree viewer, diff viewer, error highlighting
- Enhanced settings: model browser, safety levels, temperature/max tokens
- Toolbar fix: buttons no longer disappear when panels are open

### v0.2.0 — Glass UI & Performance (2025-04-15)
- Glass UI redesign with material backgrounds
- Performance optimization (dirty region tracking, render batching)
- Full prediction engine with 7-signal scoring
- N-gram command sequence learning
- Mouse reporting and hyperlink support

### v0.1.0 — Initial Release
- Complete VT100/xterm terminal emulator
- Multi-panel workspace with splits and tabs
- System monitor with live metrics
- Saved commands with templates
- Command palette
- 6 built-in themes

---

## License

MIT License. See [LICENSE](LICENSE) for details.

---

<p align="center">
  Built with care by <a href="https://github.com/Worth-Doing">Worth-Doing</a>
</p>
