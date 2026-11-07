import PolkaCore
import SwiftUI
@preconcurrency import Translation

/// Translator section: type or paste, and the translation appears as you go.
/// Uses Apple's on-device Translation framework, so text never leaves the Mac
/// and nothing needs an account or a key.
struct TranslatorSection: View {
    var body: some View {
        if #available(macOS 15, *) {
            TranslatorPane()
        } else {
            VStack(spacing: 10) {
                Image(systemName: "character.bubble")
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.secondary)
                Text("Translator needs macOS 15", tableName: "Translator")
                    .font(.system(size: 15, weight: .semibold))
                Text("It uses the translation built into newer versions of macOS.", tableName: "Translator")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

@available(macOS 15, *)
private struct TranslatorPane: View {
    @Environment(AppModel.self) private var app
    @State private var translator = TranslatorModel.shared
    @State private var configuration: TranslationSession.Configuration?
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            languageBar
            HStack(spacing: 12) {
                inputCard
                outputCard
            }
            .frame(maxHeight: .infinity)
            recent
        }
        .task(id: translator.requestKey) { await schedule() }
        .task { await loadLanguages() }
        .translationTask(configuration) { session in
            await TranslationRunner.run(session)
        }
        .onChange(of: translator.focusRequest) { inputFocused = true }
        .onChange(of: inputFocused) { _, focused in app.panel.isEditingText = focused }
        .onAppear { inputFocused = true }
    }

    // MARK: Languages

    private var languageBar: some View {
        HStack(spacing: 8) {
            languageMenu(selection: $translator.primary)
            Button {
                translator.swapLanguages()
            } label: {
                Image(systemName: "arrow.left.arrow.right")
            }
            .buttonStyle(IconButtonStyle(size: 28))
            .help(Text("Swap languages", tableName: "Translator"))
            languageMenu(selection: $translator.secondary)
            Spacer()
            if !SelectedText.isAllowed {
                Button {
                    SelectedText.requestAccess()
                } label: {
                    Label(String(localized: "Translate selection with ⌥⇧T", table: "Translator"), systemImage: "hand.raised")
                }
                .buttonStyle(.plain)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.tertiary)
                .help(Text("Polka needs Accessibility access to read the text you select in other apps.", tableName: "Translator"))
            } else {
                Text("⌥⇧T translates the selection", tableName: "Translator")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.tertiary)
            }
        }
    }

    private func languageMenu(selection: Binding<String>) -> some View {
        let codes = translator.supportedLanguages.isEmpty
            ? [translator.primary, translator.secondary]
            : translator.supportedLanguages
        return Menu {
            Picker(selection: selection) {
                ForEach(codes, id: \.self) { code in
                    Text(TranslatorModel.displayName(of: code)).tag(code)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 5) {
                Text(TranslatorModel.displayName(of: selection.wrappedValue))
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Theme.card, in: .capsule)
            .contentShape(.capsule)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: Text

    private var inputCard: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if let detected = translator.detected {
                        CardLabel(LocalizedStringKey(TranslatorModel.displayName(of: detected)))
                    } else {
                        Text("Text", tableName: "Translator").cardLabelStyle()
                    }
                    Spacer()
                    if !translator.input.isEmpty {
                        Button {
                            translator.clear()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.tertiary)
                        .help(Text("Clear", tableName: "Translator"))
                    }
                }
                TextField(
                    String(localized: "Type or paste text", table: "Translator"),
                    text: $translator.input, axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .lineLimit(2...9)
                .focused($inputFocused)
                .onSubmit { copy() }
                Spacer(minLength: 0)
            }
        }
    }

    private var outputCard: some View {
        Card(padding: 14, highlight: translator.output.isEmpty ? nil : Theme.accent.opacity(0.6)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if let target = translator.target {
                        CardLabel(LocalizedStringKey(TranslatorModel.displayName(of: target)))
                    } else {
                        Text("Translation", tableName: "Translator").cardLabelStyle()
                    }
                    Spacer()
                    if translator.isWorking {
                        ProgressView().controlSize(.mini)
                    }
                }
                ScrollView {
                    Group {
                        if let error = translator.errorText {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(error).foregroundStyle(Theme.warning).font(.system(size: 13))
                                    .fixedSize(horizontal: false, vertical: true)
                                if translator.needsLanguageDownload {
                                    Button(String(localized: "Open Language & Region", table: "Translator")) {
                                        app.panel.collapse()
                                        if let url = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension") {
                                            NSWorkspace.shared.open(url)
                                        }
                                    }.buttonStyle(CapsuleButtonStyle())
                                    Button(String(localized: "Try again", table: "Translator")) { translator.retry() }
                                        .buttonStyle(.plain).foregroundStyle(Theme.secondary)
                                }
                            }
                        } else {
                            Text(translator.output)
                                .font(.system(size: 15))
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.never)
                HStack(spacing: 8) {
                    Spacer()
                    if !translator.output.isEmpty {
                        Button {
                            translator.reverse()
                        } label: {
                            Label(String(localized: "Translate back", table: "Translator"), systemImage: "arrow.uturn.backward")
                        }
                        .buttonStyle(CapsuleButtonStyle())
                        Button {
                            copy()
                        } label: {
                            Label(String(localized: "Copy", table: "Translator"), systemImage: "doc.on.doc")
                        }
                        .buttonStyle(CapsuleButtonStyle(prominent: true))
                        .keyboardShortcut(.return, modifiers: .command)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var recent: some View {
        let entries = Array(translator.history.entries.dropFirst(translator.output.isEmpty ? 0 : 1).prefix(3))
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(entries) { entry in
                    Button {
                        translator.load(entry.text)
                    } label: {
                        HStack(spacing: 8) {
                            Text(entry.text).lineLimit(1)
                            Image(systemName: "arrow.right").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.tertiary)
                            Text(entry.translation).lineLimit(1).foregroundStyle(Theme.secondary)
                            Spacer(minLength: 0)
                        }
                        .font(.system(size: 12))
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .hoverHighlight(cornerRadius: 8)
                }
            }
        }
    }

    // MARK: Actions

    private func copy() {
        guard !translator.output.isEmpty else { return }
        translator.copyOutput()
        app.panel.flash(.init(symbol: "doc.on.doc", text: String(localized: "Translation copied", table: "Translator")))
    }

    /// Waits for a pause in typing, then points the session at the right pair.
    private func schedule() async {
        try? await Task.sleep(for: .milliseconds(280))
        guard !Task.isCancelled, let request = translator.makeRequest() else { return }
        let source = request.source.map { Locale.Language(identifier: $0) }
        let target = Locale.Language(identifier: request.target)
        let availability = LanguageAvailability()
        let status: LanguageAvailability.Status
        do {
            if let source {
                status = await availability.status(from: source, to: target)
            } else {
                status = try await availability.status(for: request.text, to: target)
            }
        } catch {
            translator.fail(request, message: String(localized: "Could not identify the language. Try a longer text.", table: "Translator"))
            return
        }
        guard !Task.isCancelled, translator.pending == request else { return }
        switch status {
        case .installed: break
        case .supported:
            translator.fail(request, message: String(localized: "Download the required translation languages in System Settings, then try again.", table: "Translator"), needsDownload: true)
            return
        case .unsupported:
            translator.fail(request, message: String(localized: "This language pair is not supported on this Mac.", table: "Translator"))
            return
        @unknown default:
            translator.fail(request, message: String(localized: "Translation language availability is unknown.", table: "Translator"))
            return
        }
        if configuration?.source == source, configuration?.target == target {
            configuration?.invalidate()
        } else {
            configuration = TranslationSession.Configuration(source: source, target: target)
        }
    }

    private func loadLanguages() async {
        guard translator.supportedLanguages.isEmpty else { return }
        let languages = await LanguageAvailability().supportedLanguages
        var seen = Set<String>()
        let codes = languages.compactMap { $0.languageCode?.identifier }.filter { seen.insert($0).inserted }
        translator.setSupportedLanguages(codes.sorted {
            TranslatorModel.displayName(of: $0).localizedStandardCompare(TranslatorModel.displayName(of: $1)) == .orderedAscending
        })
    }
}

/// Runs one translation with the session SwiftUI provides. Kept outside the
/// view so it works the same whichever actor SwiftUI calls it on.
@available(macOS 15, *)
private enum TranslationRunner {
    static func run(_ session: TranslationSession) async {
        guard let request = await MainActor.run(body: { TranslatorModel.shared.pending }) else { return }
        do {
            let response = try await session.translate(request.text)
            let text = response.targetText
            await MainActor.run { TranslatorModel.shared.finish(request, translation: text) }
        } catch {
            let message = Self.message(for: error)
            await MainActor.run { TranslatorModel.shared.fail(request, message: message) }
        }
    }

    private static func message(for error: Error) -> String {
        let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        let hint = String(
            localized: "If the languages aren’t downloaded yet, add them in System Settings › General › Language & Region › Translation Languages.",
            table: "Translator")
        return reason + "\n\n" + hint
    }
}

private extension Text {
    func cardLabelStyle() -> some View {
        font(.system(size: 11, weight: .semibold))
            .textCase(.uppercase)
            .kerning(0.3)
            .foregroundStyle(Theme.tertiary)
    }
}
