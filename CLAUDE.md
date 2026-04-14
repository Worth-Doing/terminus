# Terminus

Next-generation macOS terminal application built in Swift + SwiftUI.

## Build & Run

```bash
swift build              # Compile
swift run Terminus       # Run in development
swift test               # Run tests
swift build -c release   # Release build
./Scripts/bundle-app.sh  # Create .app bundle
```

## Architecture

- Zero external dependencies — uses only system frameworks (SQLite3, Security, Accelerate, Foundation, SwiftUI, AppKit)
- 16 modules organized as Swift package targets
- Swift 6 language mode with strict concurrency

## Module Overview

| Module | Purpose |
|--------|---------|
| Terminus | App entry point (@main) |
| SharedModels | All data types |
| DataStore | SQLite wrapper + schema |
| SecureStorage | Keychain wrapper |
| SharedUI | Theme + design system |
| TerminalCore | PTY lifecycle |
| TerminalEmulator | VT100 parser + buffer |
| TerminalUI | Canvas rendering + input |
| WorkspaceEngine | Panel tree + splits |
| HistoryEngine | Command history |
| PredictionEngine | Smart suggestions |
| SavedCommands | Saved command CRUD |
| AIService | OpenRouter client |
| EmbeddingPipeline | Vector search |
| OnboardingUI | First-run flow |
| SettingsUI | Preferences |

## Key Conventions

- Use `@Observable` (not `ObservableObject`)
- Use Swift structured concurrency (async/await, actors)
- Actor for shared mutable state (`PTYProcess`, `AIServiceClient`)
- `@unchecked Sendable` with `NSLock` for hot paths (`TerminalBuffer`)
- Canvas-based rendering for terminal (not Text views)
- All AI features are optional and never auto-execute commands
