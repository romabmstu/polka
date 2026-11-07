import PolkaCore
import PolkaSystem
import SwiftUI
import UniformTypeIdentifiers

struct TabsSection: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let tabs = app.tabs
        if let error = tabs.loadError, !tabs.isLoaded {
            Placeholder(symbol: "exclamationmark.triangle", title: "Tabs are unavailable", message: LocalizedStringKey(error))
        } else {
            HStack(alignment: .top, spacing: 14) {
                GroupList()
                    .frame(width: 196)
                VStack(alignment: .leading, spacing: 12) {
                    CurrentPageBar()
                    if tabs.query.isEmpty {
                        GroupDetail()
                    } else {
                        SearchResults()
                    }
                }
            }
        }
    }
}

// MARK: - Groups column

private struct GroupList: View {
    @Environment(AppModel.self) private var app
    @State private var isCreating = false
    @State private var newName = ""
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        @Bindable var tabs = app.tabs
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.tertiary)
                TextField("Search", text: $tabs.query)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .onChange(of: isSearchFocused) { _, focused in app.panel.isEditingText = focused }
                if !tabs.query.isEmpty {
                    Button { tabs.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.tertiary)
                        .accessibilityLabel(Text("Clear search"))
                }
            }
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(Theme.card, in: .rect(cornerRadius: 10, style: .continuous))

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(tabs.library.orderedGroups) { group in
                        GroupRow(group: group, isSelected: tabs.selectedGroup?.id == group.id && tabs.query.isEmpty)
                    }
                }
            }
            .scrollIndicators(.never)

            Button {
                newName = ""
                isCreating = true
            } label: {
                Label("New Group", systemImage: "plus")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .hoverHighlight(cornerRadius: 10)
            .popover(isPresented: $isCreating, arrowEdge: .trailing) {
                NameEditor(title: "New Group", name: $newName, confirm: "Create") {
                    tabs.createGroup(named: newName)
                    isCreating = false
                }
            }
        }
    }
}

private struct GroupRow: View {
    @Environment(AppModel.self) private var app
    let group: TabGroup
    let isSelected: Bool
    @State private var isTargeted = false

    var body: some View {
        Button {
            app.tabs.query = ""
            app.tabs.selectedGroupID = group.id
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(group.color.color)
                    .frame(width: 9, height: 9)
                    .shadow(color: group.color.color.opacity(0.6), radius: 3)
                Text(group.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if group.isPinned {
                    Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(Theme.tertiary)
                }
                Text(group.tabs.count, format: .number)
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(Theme.tertiary)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(
                isTargeted ? Theme.accent.opacity(0.25) : (isSelected ? Color.white.opacity(0.12) : .clear),
                in: .rect(cornerRadius: 10, style: .continuous)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .hoverHighlight(cornerRadius: 10)
        .dropDestination(for: URL.self) { urls, _ in
            accept(urls)
        } isTargeted: { isTargeted = $0 }
        .contextMenu { GroupMenu(group: group) }
    }

    /// A dropped URL is either one of our own tabs being moved (it carries the
    /// tab's address) or a link dragged in from a browser.
    private func accept(_ urls: [URL]) -> Bool {
        let tabs = app.tabs
        var outside: [PageReference] = []
        for url in urls {
            if let source = tabs.library.groups.first(where: { $0.id != group.id && $0.contains(url) }),
                let tab = source.tabs.first(where: { URLNormalizer.identity(of: $0.url) == URLNormalizer.identity(of: url) })
            {
                tabs.moveTab(tab.id, to: group.id)
            } else {
                outside.append(PageReference(url: url))
            }
        }
        if !outside.isEmpty { tabs.add(outside, to: group.id) }
        return true
    }
}

// MARK: - Current Safari tab

private struct CurrentPageBar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let tabs = app.tabs
        HStack(spacing: 12) {
            switch tabs.safariState {
            case .notAuthorized:
                Image(systemName: "hand.raised.fill").foregroundStyle(Theme.warning)
                Text("Allow Polka to control Safari to save the open tab.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.secondary)
                Spacer()
                Button("Open Settings") { SystemSettings.open(.automation) }
                    .buttonStyle(CapsuleButtonStyle())
            case .ready where tabs.currentPage != nil:
                if let page = tabs.currentPage {
                    SiteBadge(site: URLNormalizer.readableForm(of: page.url), size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        CardLabel("Open in Safari")
                        Text(page.title.isEmpty ? URLNormalizer.readableForm(of: page.url) : page.title)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    saveButton(for: page)
                }
            default:
                Image(systemName: "safari").foregroundStyle(Theme.tertiary)
                Text("Open a page in Safari to save it here, or drag a link onto a group.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.secondary)
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 50)
        .background(Theme.card, in: .rect(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func saveButton(for page: PageReference) -> some View {
        let tabs = app.tabs
        let target = tabs.selectedGroup ?? tabs.library.orderedGroups[0]
        if target.contains(page.url) {
            Label("Saved", systemImage: "checkmark")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Theme.active)
                .padding(.horizontal, 10)
        } else {
            Button {
                tabs.add([page], to: target.id)
            } label: {
                Text("Save to “\(target.name)”").lineLimit(1)
            }
            .buttonStyle(CapsuleButtonStyle(prominent: true))
            .keyboardShortcut("s", modifiers: .command)
        }
    }
}

// MARK: - Selected group

private struct GroupDetail: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        if let group = app.tabs.selectedGroup {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(group.name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    Text(group.tabs.count, format: .number)
                        .font(.system(size: 13).monospacedDigit())
                        .foregroundStyle(Theme.tertiary)
                    Spacer()
                    Menu {
                        GroupMenu(group: group)
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.system(size: 14, weight: .semibold))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help(Text("Group options"))
                    Button("New Window") { Task { await app.tabs.openGroup(group, inNewWindow: true) } }
                        .buttonStyle(CapsuleButtonStyle())
                        .disabled(group.tabs.isEmpty)
                    Button("Open All") { Task { await app.tabs.openGroup(group, inNewWindow: false) } }
                        .buttonStyle(CapsuleButtonStyle(prominent: true))
                        .disabled(group.tabs.isEmpty)
                }
                if group.tabs.isEmpty {
                    Placeholder(
                        symbol: "square.dashed",
                        title: "Nothing here yet",
                        message: "Save the open Safari tab, drag links onto this group or press ⌘V to paste a list of links.")
                } else {
                    TabGrid(group: group, tabs: group.sortedTabs)
                }
            }
            .onPasteCommand(of: [.url, .plainText]) { _ in
                PasteHandler.addLinks(to: group.id, app: app)
            }
        }
    }
}

private struct SearchResults: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let results = app.tabs.library.search(app.tabs.query)
        if results.isEmpty {
            Placeholder(symbol: "magnifyingglass", title: "No matches", message: "Try another word from the title, address or note.")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(results, id: \.group.id) { result in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Circle().fill(result.group.color.color).frame(width: 7, height: 7)
                                Text(result.group.name).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondary)
                            }
                            TabGrid(group: result.group, tabs: result.tabs, scrolls: false)
                        }
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }
}

// MARK: - Tabs

private struct TabGrid: View {
    let group: TabGroup
    let tabs: [SavedTab]
    var scrolls = true

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        let grid = LazyVGrid(columns: columns, spacing: 8) {
            ForEach(tabs) { tab in
                TabTile(group: group, tab: tab)
            }
        }
        if scrolls {
            ScrollView { grid }.scrollIndicators(.never)
        } else {
            grid
        }
    }
}

private struct TabTile: View {
    @Environment(AppModel.self) private var app
    let group: TabGroup
    let tab: SavedTab
    @State private var isEditing = false
    @State private var isTargeted = false

    var body: some View {
        Button {
            app.tabs.open(tab)
            if app.preferences.closeAfterOpeningTab, !app.panel.isPinned { app.panel.collapse() }
        } label: {
            HStack(spacing: 10) {
                SiteBadge(site: tab.site, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tab.displayTitle).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    HStack(spacing: 4) {
                        Text(tab.site)
                        if !tab.note.isEmpty {
                            Text("·")
                            Text(tab.note).italic()
                        }
                    }
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.tertiary)
                    .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(Theme.card, in: .rect(cornerRadius: 12, style: .continuous))
            .overlay {
                if isTargeted {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.accent, lineWidth: 1.5)
                }
            }
            .hoverHighlight(cornerRadius: 12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(Text(tab.url.absoluteString))
        .draggable(tab.url)
        .dropDestination(for: URL.self) { urls, _ in
            reorder(urls)
        } isTargeted: { isTargeted = $0 }
        .contextMenu { menu }
        .popover(isPresented: $isEditing, arrowEdge: .bottom) {
            TabEditor(tab: tab, groupID: group.id) { isEditing = false }
        }
    }

    @ViewBuilder
    private var menu: some View {
        Button("Open") { app.tabs.open(tab) }
        Button("Open in New Window") {
            Task { try? await SafariBridge().open([tab.url], inNewWindow: true) }
        }
        Divider()
        Button("Edit…") { isEditing = true }
        Menu("Move To") {
            ForEach(app.tabs.library.orderedGroups.filter { $0.id != group.id }) { other in
                Button(other.name) { app.tabs.moveTab(tab.id, to: other.id) }
            }
        }
        Button("Copy Link") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(tab.url.absoluteString, forType: .string)
        }
        Divider()
        Button("Delete", role: .destructive) {
            app.tabs.removeTab(tab.id)
            app.panel.flash(.init(symbol: "trash", text: String(localized: "Tab deleted"), canUndo: true))
        }
    }

    /// Dropping a tile onto another reorders within the group; dropping a link
    /// from outside inserts it at that spot.
    private func reorder(_ urls: [URL]) -> Bool {
        let tabs = app.tabs
        for url in urls {
            let key = URLNormalizer.identity(of: url)
            if let moving = tabs.library.groups.lazy.flatMap(\.tabs).first(where: { URLNormalizer.identity(of: $0.url) == key }) {
                tabs.moveTab(moving.id, to: group.id, before: tab.id)
            } else {
                let index = group.tabs.firstIndex { $0.id == tab.id }
                tabs.add([PageReference(url: url)], to: group.id, at: index)
            }
        }
        return true
    }
}

// MARK: - Editors and menus

struct GroupMenu: View {
    @Environment(AppModel.self) private var app
    let group: TabGroup

    var body: some View {
        let tabs = app.tabs
        Button("Open All") { Task { await tabs.openGroup(group, inNewWindow: false) } }
        Button("Open and Clear Group") {
            Task { await tabs.openGroup(group, inNewWindow: false, removeAfterwards: true) }
        }
        Divider()
        Picker("Sort Tabs", selection: Binding(get: { group.sortOrder }, set: { order in tabs.updateGroup(group.id) { $0.sortOrder = order } })) {
            Text("Manually").tag(TabGroup.SortOrder.manual)
            Text("By Title").tag(TabGroup.SortOrder.title)
            Text("Newest First").tag(TabGroup.SortOrder.newestFirst)
            Text("By Site").tag(TabGroup.SortOrder.site)
            Text("Recently Opened").tag(TabGroup.SortOrder.recentlyOpened)
        }
        Picker("Color", selection: Binding(get: { group.color }, set: { color in tabs.updateGroup(group.id) { $0.color = color } })) {
            ForEach(GroupColor.allCases, id: \.self) { color in
                Text(color.name).tag(color)
            }
        }
        Button {
            tabs.updateGroup(group.id) { $0.isPinned.toggle() }
        } label: {
            if group.isPinned { Text("Unpin") } else { Text("Pin to Top") }
        }
        Button("Paste Links") { PasteHandler.addLinks(to: group.id, app: app) }
        Button("Rename…") { RenamePrompt.show(group: group, tabs: tabs) }
        Button("Copy Links as Markdown") {
            let text = group.sortedTabs.map { "- [\($0.displayTitle)](\($0.url.absoluteString))" }.joined(separator: "\n")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
        Divider()
        Button("Delete Group", role: .destructive) {
            tabs.deleteGroup(group.id)
            app.panel.flash(.init(symbol: "trash", text: String(localized: "Group deleted"), canUndo: true))
        }
    }
}

/// A small sheet-less prompt for renaming, shown as an alert because context
/// menus cannot host text fields.
@MainActor
enum RenamePrompt {
    static func show(group: TabGroup, tabs: TabsModel) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Rename Group")
        let field = NSTextField(string: group.name)
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "Rename"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.window.initialFirstResponder = field
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { tabs.updateGroup(group.id) { $0.name = name } }
        }
    }
}

private struct NameEditor: View {
    let title: LocalizedStringKey
    @Binding var name: String
    let confirm: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .onSubmit(submit)
            HStack {
                Spacer()
                Button(confirm, action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(14)
    }

    private func submit() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        action()
    }
}

private struct TabEditor: View {
    @Environment(AppModel.self) private var app
    let tab: SavedTab
    let groupID: UUID
    let done: () -> Void

    @State private var title = ""
    @State private var address = ""
    @State private var note = ""

    var body: some View {
        Form {
            TextField("Title", text: $title)
            TextField("Address", text: $address)
            TextField("Note", text: $note, axis: .vertical)
                .lineLimit(2...4)
        }
        .formStyle(.columns)
        .frame(width: 320)
        .padding(14)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button("Cancel", action: done).keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(URLNormalizer.url(fromUserInput: address) == nil)
            }
            .padding([.horizontal, .bottom], 14)
        }
        .onAppear {
            title = tab.title
            address = tab.url.absoluteString
            note = tab.note
        }
    }

    private func save() {
        guard let url = URLNormalizer.url(fromUserInput: address) else { return }
        app.tabs.updateTab(tab.id) {
            $0.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            $0.url = url
            $0.note = String(note.prefix(500))
        }
        done()
    }
}

/// Adds every link found on the pasteboard — a single URL, a list, Markdown
/// or a OneTab export — to a group.
@MainActor
enum PasteHandler {
    static func addLinks(to groupID: UUID, app: AppModel) {
        let pasteboard = NSPasteboard.general
        var pages = LinkExtractor.pages(in: pasteboard.string(forType: .string) ?? "")
        if pages.isEmpty, let url = pasteboard.readObjects(forClasses: [NSURL.self])?.first as? URL {
            pages = [PageReference(url: url)]
        }
        guard !pages.isEmpty else {
            app.panel.flash(.init(symbol: "link", text: String(localized: "No links on the clipboard")))
            return
        }
        let result = app.tabs.add(pages, to: groupID)
        app.panel.flash(.init(symbol: "link", text: String(localized: "Added \(result.added.count) links")))
    }
}

enum SystemSettings {
    enum Pane: String {
        case automation = "Privacy_Automation"
        case accessibility = "Privacy_Accessibility"
        case calendars = "Privacy_Calendars"
    }

    @MainActor
    static func open(_ pane: Pane) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane.rawValue)") {
            NSWorkspace.shared.open(url)
        }
    }
}
