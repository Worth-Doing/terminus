// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Terminus",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Terminus", targets: ["Terminus"]),
    ],
    dependencies: [],
    targets: [
        // ── Executable ──────────────────────────────────────────────
        .executableTarget(
            name: "Terminus",
            dependencies: [
                "TerminalUI",
                "WorkspaceEngine",
                "OnboardingUI",
                "SettingsUI",
                "SharedUI",
                "DataStore",
                "SecureStorage",
                "PredictionEngine",
                "AIService",
                "HistoryEngine",
                "SavedCommands",
                "EmbeddingPipeline",
                "SystemMonitor",
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        // ── Foundation ──────────────────────────────────────────────
        .target(
            name: "SharedModels",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "DataStore",
            dependencies: ["SharedModels"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-Xcc", "-I/usr/include"]),
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
        .target(
            name: "SecureStorage",
            dependencies: ["SharedModels"],
            swiftSettings: [.swiftLanguageMode(.v6)],
            linkerSettings: [
                .linkedFramework("Security"),
            ]
        ),
        .target(
            name: "SharedUI",
            dependencies: ["SharedModels"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        // ── Terminal Engine ─────────────────────────────────────────
        .target(
            name: "TerminalCore",
            dependencies: ["SharedModels"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "TerminalEmulator",
            dependencies: ["SharedModels"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "TerminalUI",
            dependencies: [
                "TerminalEmulator",
                "TerminalCore",
                "SharedUI",
                "SharedModels",
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        // ── Workspace ───────────────────────────────────────────────
        .target(
            name: "WorkspaceEngine",
            dependencies: ["TerminalUI", "SharedModels"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        // ── Intelligence ────────────────────────────────────────────
        .target(
            name: "HistoryEngine",
            dependencies: ["DataStore", "SharedModels"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "PredictionEngine",
            dependencies: ["HistoryEngine", "SharedModels"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "SavedCommands",
            dependencies: ["DataStore", "SharedModels", "SharedUI"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        // ── AI Layer ────────────────────────────────────────────────
        .target(
            name: "AIService",
            dependencies: ["SecureStorage", "SharedModels"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "EmbeddingPipeline",
            dependencies: ["AIService", "DataStore", "SharedModels"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ],
            linkerSettings: [
                .linkedFramework("Accelerate"),
            ]
        ),

        // ── System Monitor ──────────────────────────────────────────
        .target(
            name: "SystemMonitor",
            dependencies: ["SharedModels"],
            swiftSettings: [.swiftLanguageMode(.v6)],
            linkerSettings: [
                .linkedFramework("IOKit"),
            ]
        ),

        // ── UI Modules ──────────────────────────────────────────────
        .target(
            name: "OnboardingUI",
            dependencies: ["SharedUI", "SecureStorage", "SharedModels"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "SettingsUI",
            dependencies: ["SharedUI", "SecureStorage", "SharedModels"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        // ── Tests ───────────────────────────────────────────────────
        .testTarget(
            name: "TerminalEmulatorTests",
            dependencies: ["TerminalEmulator"]
        ),
        .testTarget(
            name: "PredictionEngineTests",
            dependencies: ["PredictionEngine"]
        ),
        .testTarget(
            name: "DataStoreTests",
            dependencies: ["DataStore"]
        ),
    ]
)
