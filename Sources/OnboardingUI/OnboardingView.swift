import SwiftUI
import SharedModels
import SharedUI
import SecureStorage

// MARK: - Onboarding Step

enum OnboardingStep: Int, CaseIterable {
    case welcome
    case features
    case apiKey
    case ready
}

// MARK: - Onboarding View

public struct OnboardingView: View {
    @State private var currentStep: OnboardingStep = .welcome
    @State private var apiKey: String = ""
    @State private var apiKeyError: String?
    @State private var isValidating: Bool = false

    private let secureStorage: SecureStorage
    private let theme: TerminusTheme
    private let onComplete: () -> Void

    public init(
        secureStorage: SecureStorage = SecureStorage(),
        theme: TerminusTheme = .defaultLight,
        onComplete: @escaping () -> Void
    ) {
        self.secureStorage = secureStorage
        self.theme = theme
        self.onComplete = onComplete
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            HStack(spacing: TerminusDesign.spacingSM) {
                ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                    Capsule()
                        .fill(step.rawValue <= currentStep.rawValue
                              ? TerminusAccent.primary
                              : theme.chromeDivider)
                        .frame(height: 3)
                }
            }
            .padding(.horizontal, TerminusDesign.spacingXL)
            .padding(.top, TerminusDesign.spacingLG)

            Spacer()

            // Content
            Group {
                switch currentStep {
                case .welcome:
                    welcomeContent
                case .features:
                    featuresContent
                case .apiKey:
                    apiKeyContent
                case .ready:
                    readyContent
                }
            }
            .transition(.opacity.combined(with: .move(edge: .trailing)))

            Spacer()

            // Navigation
            HStack {
                if currentStep != .welcome {
                    Button("Back") {
                        withAnimation(.easeInOut(duration: TerminusDesign.animationNormal)) {
                            if let prev = OnboardingStep(rawValue: currentStep.rawValue - 1) {
                                currentStep = prev
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.chromeTextSecondary)
                }

                Spacer()

                Button(currentStep == .ready ? "Launch Terminus" : "Continue") {
                    handleNext()
                }
                .buttonStyle(.borderedProminent)
                .tint(TerminusAccent.primary)
                .disabled(isValidating)
            }
            .padding(TerminusDesign.spacingXL)
        }
        .frame(width: 600, height: 450)
        .background(theme.chromeBackground)
    }

    // MARK: - Content Views

    private var welcomeContent: some View {
        VStack(spacing: TerminusDesign.spacingLG) {
            Text("Terminus")
                .font(.terminusUI(size: 42, weight: .bold))
                .foregroundStyle(theme.chromeText)

            Text("The terminal that learns how you work.")
                .font(.terminusUI(size: 18, weight: .medium))
                .foregroundStyle(theme.chromeTextSecondary)
        }
    }

    private var featuresContent: some View {
        VStack(alignment: .leading, spacing: TerminusDesign.spacingLG) {
            featureRow(
                icon: "rectangle.split.3x1",
                title: "Multi-Panel Workspace",
                description: "Split, resize, and navigate between panels effortlessly."
            )
            featureRow(
                icon: "brain",
                title: "Smart Predictions",
                description: "Learns your command patterns and suggests continuations."
            )
            featureRow(
                icon: "bookmark",
                title: "Saved Commands",
                description: "Save, tag, and reuse complex commands with parameters."
            )
            featureRow(
                icon: "sparkles",
                title: "AI Assistance",
                description: "Optional OpenRouter-powered command help and semantic search."
            )
        }
        .padding(.horizontal, TerminusDesign.spacingXL * 2)
    }

    private var apiKeyContent: some View {
        VStack(spacing: TerminusDesign.spacingLG) {
            Text("OpenRouter API Key")
                .font(.terminusUI(size: 24, weight: .semibold))
                .foregroundStyle(theme.chromeText)

            Text("AI features are powered by OpenRouter. Enter your API key to enable them, or skip to use Terminus without AI.")
                .font(.terminusUI(size: 14))
                .foregroundStyle(theme.chromeTextSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            SecureField("sk-or-...", text: $apiKey)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 400)

            if let error = apiKeyError {
                Text(error)
                    .font(.terminusUI(size: 12))
                    .foregroundStyle(TerminusAccent.error)
            }

            Button("Skip for now") {
                withAnimation(.easeInOut(duration: TerminusDesign.animationNormal)) {
                    currentStep = .ready
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.chromeTextTertiary)
            .font(.terminusUI(size: 13))
        }
    }

    private var readyContent: some View {
        VStack(spacing: TerminusDesign.spacingLG) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(TerminusAccent.success)

            Text("You're all set.")
                .font(.terminusUI(size: 24, weight: .semibold))
                .foregroundStyle(theme.chromeText)

            Text("Terminus is ready to go.")
                .font(.terminusUI(size: 16))
                .foregroundStyle(theme.chromeTextSecondary)
        }
    }

    // MARK: - Helpers

    private func featureRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: TerminusDesign.spacingMD) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(TerminusAccent.primary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.terminusUI(size: 15, weight: .semibold))
                    .foregroundStyle(theme.chromeText)
                Text(description)
                    .font(.terminusUI(size: 13))
                    .foregroundStyle(theme.chromeTextSecondary)
            }
        }
    }

    private func handleNext() {
        withAnimation(.easeInOut(duration: TerminusDesign.animationNormal)) {
            switch currentStep {
            case .welcome, .features:
                if let next = OnboardingStep(rawValue: currentStep.rawValue + 1) {
                    currentStep = next
                }
            case .apiKey:
                if !apiKey.isEmpty {
                    saveAPIKey()
                } else {
                    currentStep = .ready
                }
            case .ready:
                onComplete()
            }
        }
    }

    private func saveAPIKey() {
        isValidating = true
        apiKeyError = nil

        do {
            try secureStorage.store(key: SecureStorage.openRouterAPIKey, value: apiKey)
            currentStep = .ready
        } catch {
            apiKeyError = "Failed to save API key: \(error.localizedDescription)"
        }

        isValidating = false
    }
}
