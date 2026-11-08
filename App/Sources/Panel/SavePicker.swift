import PolkaCore
import SwiftUI

/// Asks where to save pages coming from a browser or the Services menu.
/// Everything works from the keyboard: type to filter or name a new group,
/// ↑↓ to move, Return to save, ⌘1–⌘9 to pick a row, Esc to cancel.
struct SavePicker: View {
    @Environment(AppModel.self) private var app
    let request: SaveRequest

    @State private var scope: SaveRequest.Scope = .current
    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var searchFocused: Bool

    private enum Choice: Identifiable {
        case group(TabGroup)
        case create(String)

        var id: String {
            switch self {
            case .group(let group): group.id.uuidString
            case .create(let name): "new:" + name
            }
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            pagesColumn
                .frame(width: 265)
            Divider().overlay(Theme.hairline)
            groupsColumn
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { shortcuts }
        .onAppear { searchFocused = true }
        .onChange(of: query) { highlighted = 0 }
    }

    // MARK: What is being saved

    private var pagesColumn: some View {
        let pages = request.pages(for: scope)
        return VStack(alignment: .leading, spacing: 10) {
            CardLabel("Save from \(request.source)")
            Text("Pages to save").font(.system(size: 15, weight: .semibold))
            if request.offersWindow {
                Picker("", selection: $scope) {
                    Text("This tab").tag(SaveRequest.Scope.current)
                    Text("All tabs · \(request.window.count)").tag(SaveRequest.Scope.window)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                (scope == .current ? Text("Only the current tab") : Text("All tabs from the current browser window"))
                    .font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { _, page in
                        PageLine(page: page)
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }

    // MARK: Where to

    private var groupsColumn: some View {
        let choices = self.choices
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Choose a group").font(.system(size: 15, weight: .semibold))
                    Text("Select where to save the pages")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.secondary)
                }
                Spacer(minLength: 8)
                Button("Cancel") { app.panel.collapse() }
                    .buttonStyle(CapsuleButtonStyle()).fixedSize()
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.tertiary)
                TextField("Find a group or name a new one", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($searchFocused)
                    .onSubmit { commit(at: highlighted) }
                    .onKeyPress(.downArrow) {
                        highlighted = min(highlighted + 1, max(choices.count - 1, 0))
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        highlighted = max(highlighted - 1, 0)
                        return .handled
                    }
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(Theme.card, in: .rect(cornerRadius: 12, style: .continuous))

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(choices.enumerated()), id: \.element.id) { index, choice in
                            row(choice, index: index)
                                .id(index)
                        }
                    }
                }
                .scrollIndicators(.never)
                .onChange(of: highlighted) { proxy.scrollTo(highlighted) }
            }

            Text("↑↓ Select   ·   Return Save   ·   Esc Cancel")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var choices: [Choice] {
        let found = GroupNameSearch.results(in: app.tabs.saveTargets, name: { $0.name }, query: query)
        var result = found.matches.map(Choice.group)
        if let name = found.newGroupName { result.append(.create(name)) }
        return result
    }

    private func row(_ choice: Choice, index: Int) -> some View {
        let isHighlighted = index == highlighted
        return Button {
            commit(at: index)
        } label: {
            HStack(spacing: 10) {
                switch choice {
                case .group(let group):
                    Circle().fill(group.color.color).frame(width: 9, height: 9)
                    Text(group.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 6)
                    if alreadySaved(in: group) {
                        Label("Already here", systemImage: "checkmark")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Theme.active)
                    } else {
                        Text("\(group.tabs.count) saved")
                            .font(.system(size: 11.5).monospacedDigit())
                            .foregroundStyle(Theme.tertiary)
                            .fixedSize()
                    }
                case .create(let name):
                    Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accent)
                    Text("New group “\(name)”").font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 6)
                }
                if index < 9 {
                    Text(verbatim: "⌘\(index + 1)")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(Theme.tertiary)
                        .frame(width: 28, alignment: .trailing)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(isHighlighted ? Color.white.opacity(0.13) : .clear, in: .rect(cornerRadius: 10, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { if $0 { highlighted = index } }
    }

    /// Invisible buttons that carry the ⌘1–⌘9 shortcuts.
    private var shortcuts: some View {
        ZStack {
            ForEach(0..<9, id: \.self) { index in
                Button("") { commit(at: index) }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
            }
        }
        .opacity(0)
        .accessibilityHidden(true)
    }

    private func alreadySaved(in group: TabGroup) -> Bool {
        let pages = request.pages(for: scope)
        return !pages.isEmpty && pages.allSatisfy { group.contains($0.url) }
    }

    private func commit(at index: Int) {
        let choices = self.choices
        guard choices.indices.contains(index) else { return }
        let groupID: UUID
        switch choices[index] {
        case .group(let group): groupID = group.id
        case .create(let name): groupID = app.tabs.createGroup(named: name)
        }
        app.save(request.pages(for: scope), to: groupID)
    }
}

private struct PageLine: View {
    let page: PageReference

    var body: some View {
        let site = URLNormalizer.readableForm(of: page.url)
        HStack(spacing: 10) {
            SiteBadge(site: site, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(page.title.isEmpty ? site : page.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                Text(site)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 3)
    }
}
