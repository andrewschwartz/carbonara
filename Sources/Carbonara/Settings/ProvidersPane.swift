import AppKit
import SwiftUI

/// Settings for the generation backends: fal.ai API key and Higgsfield MCP token.
struct ProvidersPane: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xxl) {
            SettingsSection(title: "fal.ai") {
                FalKeyRow()
            }
            SettingsSection(title: "Higgsfield") {
                HiggsfieldTokenRow()
            }
        }
    }
}

// MARK: - fal.ai key

private struct FalKeyRow: View {
    @State private var hasKey = false
    @State private var maskedKey = ""
    @State private var draft = ""
    @State private var verifying = false
    @State private var verifyResult: FalKeyVerifier.Outcome?
    @FocusState private var isFocused: Bool

    private let dashboardURL = URL(string: "https://fal.ai/dashboard/keys")!

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.smMd) {
            KeyFieldHeader(
                title: "fal.ai API Key",
                blurb: "Runs image, video, and audio models on fal. Stored in the macOS Keychain.",
                linkText: "Get fal.ai key",
                url: dashboardURL
            )
            HStack(spacing: AppTheme.Spacing.sm) {
                SecureKeyField(placeholder: hasKey ? maskedKey : "fal-…", text: $draft, isFocused: $isFocused, onSubmit: save)
                let trimmed = draft.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    Button("Save", action: save)
                        .buttonStyle(.capsule(.prominent, size: .regular))
                        .controlSize(.large)
                } else if hasKey {
                    Button(action: verify) {
                        if verifying {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Verify")
                        }
                    }
                    .buttonStyle(.capsule(.secondary, size: .regular))
                    .controlSize(.large)
                    .disabled(verifying)

                    Button(action: remove) {
                        Image(systemName: "trash")
                            .font(.system(size: AppTheme.FontSize.md))
                            .foregroundStyle(AppTheme.Text.secondaryColor)
                            .frame(width: AppTheme.IconSize.md, height: AppTheme.IconSize.md)
                    }
                    .buttonStyle(.capsule(.secondary, size: .regular))
                    .controlSize(.large)
                    .help("Remove fal.ai key")
                }
            }
            if let verifyResult {
                verdictLabel(verifyResult)
            }
        }
        .onAppear(perform: refresh)
    }

    @ViewBuilder
    private func verdictLabel(_ outcome: FalKeyVerifier.Outcome) -> some View {
        switch outcome {
        case .ok:
            Label("Key verified", systemImage: "checkmark.circle.fill")
                .foregroundStyle(AppTheme.Status.successColor)
                .font(.system(size: AppTheme.FontSize.sm))
        case .rejected:
            Label("Key rejected", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.system(size: AppTheme.FontSize.sm))
        case .network(let message):
            Label("Couldn't reach fal: \(message)", systemImage: "wifi.exclamationmark")
                .foregroundStyle(AppTheme.Text.tertiaryColor)
                .font(.system(size: AppTheme.FontSize.sm))
        }
    }

    private func refresh() {
        Task { @MainActor in
            let key = await Task.detached(priority: .utility) { FalKeyStore.load() ?? "" }.value
            hasKey = !key.isEmpty
            maskedKey = KeyMask.mask(key)
        }
    }

    private func save() {
        let key = draft.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }
        draft = ""
        isFocused = false
        verifyResult = nil
        Task { @MainActor in
            await Task.detached(priority: .userInitiated) { FalKeyStore.save(key) }.value
            hasKey = true
            maskedKey = KeyMask.mask(key)
            verify()
        }
    }

    private func remove() {
        draft = ""
        verifyResult = nil
        Task { @MainActor in
            await Task.detached(priority: .userInitiated) { FalKeyStore.delete() }.value
            hasKey = false
            maskedKey = ""
        }
    }

    private func verify() {
        verifying = true
        verifyResult = nil
        Task { @MainActor in
            let key = await Task.detached(priority: .utility) { FalKeyStore.load() ?? "" }.value
            verifyResult = await FalKeyVerifier.verify(key)
            verifying = false
        }
    }
}

// MARK: - Higgsfield token

private struct HiggsfieldTokenRow: View {
    @State private var hasToken = false
    @State private var maskedToken = ""
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    private let connectURL = URL(string: "https://higgsfield.ai/mcp")!

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.smMd) {
            KeyFieldHeader(
                title: "Higgsfield Access Token",
                blurb: "Connects Carbonara to Higgsfield's MCP server for image and video generation.",
                linkText: "Higgsfield MCP",
                url: connectURL
            )
            HStack(spacing: AppTheme.Spacing.sm) {
                SecureKeyField(placeholder: hasToken ? maskedToken : "token…", text: $draft, isFocused: $isFocused, onSubmit: save)
                let trimmed = draft.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    Button("Save", action: save)
                        .buttonStyle(.capsule(.prominent, size: .regular))
                        .controlSize(.large)
                } else if hasToken {
                    Button(action: remove) {
                        Image(systemName: "trash")
                            .font(.system(size: AppTheme.FontSize.md))
                            .foregroundStyle(AppTheme.Text.secondaryColor)
                            .frame(width: AppTheme.IconSize.md, height: AppTheme.IconSize.md)
                    }
                    .buttonStyle(.capsule(.secondary, size: .regular))
                    .controlSize(.large)
                    .help("Remove Higgsfield token")
                }
            }
        }
        .onAppear(perform: refresh)
    }

    private func refresh() {
        Task { @MainActor in
            let token = await Task.detached(priority: .utility) { HiggsfieldKeyStore.load() ?? "" }.value
            hasToken = !token.isEmpty
            maskedToken = KeyMask.mask(token)
        }
    }

    private func save() {
        let token = draft.trimmingCharacters(in: .whitespaces)
        guard !token.isEmpty else { return }
        draft = ""
        isFocused = false
        Task { @MainActor in
            await Task.detached(priority: .userInitiated) { HiggsfieldKeyStore.save(token) }.value
            await HiggsfieldConnection.shared.reset()
            hasToken = true
            maskedToken = KeyMask.mask(token)
        }
    }

    private func remove() {
        draft = ""
        Task { @MainActor in
            await Task.detached(priority: .userInitiated) { HiggsfieldKeyStore.delete() }.value
            await HiggsfieldConnection.shared.reset()
            hasToken = false
            maskedToken = ""
        }
    }
}

// MARK: - Shared field pieces

private struct KeyFieldHeader: View {
    let title: String
    let blurb: String
    let linkText: String
    let url: URL

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Text(title)
                .font(.system(size: AppTheme.FontSize.md, weight: AppTheme.FontWeight.medium))
                .foregroundStyle(AppTheme.Text.primaryColor)
            HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.sm) {
                Text(blurb)
                    .font(.system(size: AppTheme.FontSize.sm))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: { NSWorkspace.shared.open(url, configuration: .init(), completionHandler: nil) }) {
                    HStack(spacing: AppTheme.Spacing.xxs) {
                        Text(linkText)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: AppTheme.FontSize.xs, weight: AppTheme.FontWeight.semibold))
                    }
                    .font(.system(size: AppTheme.FontSize.sm))
                    .foregroundStyle(AppTheme.Accent.link)
                }
                .buttonStyle(.plain)
                .fixedSize()
                .pointerStyle(.link)
            }
        }
    }
}

private struct SecureKeyField: View {
    let placeholder: String
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    let onSubmit: () -> Void

    var body: some View {
        SecureField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .focused($isFocused)
            .font(.system(size: AppTheme.FontSize.sm, design: .monospaced))
            .foregroundStyle(AppTheme.Text.primaryColor)
            .onSubmit(onSubmit)
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.smMd)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                    .fill(Color.black.opacity(AppTheme.Opacity.muted))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                    .strokeBorder(
                        isFocused ? AppTheme.Border.primaryColor : AppTheme.Border.subtleColor,
                        lineWidth: AppTheme.BorderWidth.thin
                    )
            )
            .animation(.easeOut(duration: AppTheme.Anim.hover), value: isFocused)
    }
}

enum KeyMask {
    static func mask(_ key: String) -> String {
        guard key.count > 4 else { return String(repeating: "\u{2022}", count: 32) }
        return String(repeating: "\u{2022}", count: 36) + key.suffix(4)
    }
}
