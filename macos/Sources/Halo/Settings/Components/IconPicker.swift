import AppKit
import HaloCore
import SwiftUI

/// Picks a slot icon: the action's default, an SF Symbol (searchable, by category), an emoji,
/// an app's icon, or an image file. Shows the current icon; the picker opens in a popover and
/// applies each choice immediately.
struct IconPicker: View {
    /// nil means "use `defaultIcon`".
    @Binding var icon: IconSpec?
    /// What the slot shows when `icon` is nil.
    var defaultIcon: IconSpec?

    @ViewState private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 8) {
                SlotIconTile(icon: icon ?? defaultIcon, size: 22)
                Text(summary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .popover(isPresented: $isPresented, arrowEdge: .leading) {
            IconPickerPanel(icon: $icon, defaultIcon: defaultIcon)
        }
        .onAppear { SymbolLibrary.shared.loadIfNeeded() }
        .accessibilityLabel("Icon")
        .accessibilityValue(summary)
        .accessibilityHint("Opens the icon picker")
    }

    private var summary: String {
        switch icon {
        case nil: "Default"
        case .symbol(let name): name
        case .app(let bundleID): AppCatalog.shared.info(bundleID: bundleID)?.name ?? "App Icon"
        case .image: "Custom Image"
        case .emoji(let text): text
        }
    }
}

private struct IconPickerPanel: View {
    @Binding var icon: IconSpec?
    let defaultIcon: IconSpec?

    @ViewState private var tab: Tab

    enum Tab: String, CaseIterable, Identifiable {
        case standard = "Default"
        case symbol = "Symbol"
        case emoji = "Emoji"
        case app = "App"
        case image = "Image"

        var id: Self { self }

        init(_ icon: IconSpec?) {
            switch icon {
            case nil: self = .standard
            case .symbol: self = .symbol
            case .emoji: self = .emoji
            case .app: self = .app
            case .image: self = .image
            }
        }
    }

    init(icon: Binding<IconSpec?>, defaultIcon: IconSpec?) {
        self._icon = icon
        self.defaultIcon = defaultIcon
        self._tab = ViewState(initialValue: Tab(icon.wrappedValue))
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Icon Type", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)

            Divider()

            Group {
                switch tab {
                case .standard: DefaultIconTab(icon: $icon, defaultIcon: defaultIcon)
                case .symbol: SymbolIconTab(icon: $icon)
                case .emoji: EmojiIconTab(icon: $icon)
                case .app: AppIconTab(icon: $icon)
                case .image: ImageIconTab(icon: $icon)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 380, height: 470)
    }
}

// MARK: - Default

private struct DefaultIconTab: View {
    @Binding var icon: IconSpec?
    let defaultIcon: IconSpec?

    var body: some View {
        VStack(spacing: 14) {
            SlotIconTile(icon: defaultIcon, size: 72)
            Text("The action's own icon: the app's icon for apps, a matching symbol for everything else.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
            Button(icon == nil ? "Using Default Icon" : "Use Default Icon") { icon = nil }
                .disabled(icon == nil)
        }
        .padding()
    }
}

// MARK: - SF Symbols

private struct SymbolIconTab: View {
    @Binding var icon: IconSpec?
    @ViewState private var query = ""
    @ViewState private var category = "all"

    private var selectedName: String? {
        if case .symbol(let name) = icon { return name }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                PickerSearchField(prompt: "Search Symbols", text: $query)
                if let catalog = SymbolLibrary.shared.catalog {
                    Picker("Category", selection: $category) {
                        ForEach(catalog.categories) { c in
                            Label(c.title, systemImage: c.symbol).tag(c.key)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityLabel("Symbol category")
                }
            }
            .padding(10)

            if let catalog = SymbolLibrary.shared.catalog {
                let names = catalog.symbols(in: category, matching: query)
                if names.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    grid(names)
                }
            } else {
                ProgressView("Loading Symbols…")
                    .frame(maxHeight: .infinity)
            }
        }
        .onAppear { SymbolLibrary.shared.loadIfNeeded() }
    }

    private func grid(_ names: [String]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 40, maximum: 48), spacing: 4)], spacing: 4) {
                    ForEach(names, id: \.self) { name in
                        let isSelected = name == selectedName
                        Button {
                            icon = .symbol(name: name)
                        } label: {
                            Image(systemName: name)
                                .font(.system(size: 18))
                                .symbolRenderingMode(.hierarchical)
                                .frame(width: 40, height: 40)
                                .background(isSelected ? Color.accentColor.opacity(0.22) : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                .overlay {
                                    if isSelected {
                                        RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.accentColor, lineWidth: 1.5)
                                    }
                                }
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(name)
                        .accessibilityLabel(name.replacingOccurrences(of: ".", with: " "))
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        .id(name)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
            .onAppear {
                if let selectedName, names.contains(selectedName) { proxy.scrollTo(selectedName, anchor: .center) }
            }
        }
    }
}

// MARK: - Emoji

private struct EmojiIconTab: View {
    @Binding var icon: IconSpec?
    @ViewState private var typed = ""
    @FocusState private var fieldFocused: Bool

    private static let emoji: [String] = [
        "😀", "😎", "🤓", "🤖", "👋", "👍", "🙏", "👀", "🧠", "💡", "🔥", "✨", "⭐️", "❤️", "✅", "❌",
        "⚡️", "🚀", "🎯", "📌", "📎", "📝", "📚", "📁", "🗂️", "🗓️", "⏰", "🔔", "🔒", "🔑", "🛠️", "⚙️",
        "🧰", "🧪", "💻", "🖥️", "⌨️", "🖱️", "📱", "🎧", "🎵", "🎬", "📷", "🎨", "✏️", "🖌️", "📐", "📊",
        "📈", "💬", "✉️", "📮", "🌐", "🔍", "🏠", "🏢", "🛒", "💳", "💰", "🎁", "☕️", "🍕", "🌙", "☀️",
        "🌧️", "❄️", "🌈", "🌱", "🐶", "🐱", "🦊", "🐼", "🐝", "🦄", "🏃", "🧘", "🎮", "🏆", "⚽️", "🎲",
        "🧩", "🗑️", "♻️", "🔄", "⏯️", "⏭️", "⏮️", "🔊", "🔇", "💤", "🔋", "🔌", "📡", "🎉", "🪄", "🧭",
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("Type or paste an emoji", text: $typed)
                    .textFieldStyle(.roundedBorder)
                    .focused($fieldFocused)
                    .accessibilityLabel("Emoji")
                Button("Emoji & Symbols", systemImage: "face.smiling") {
                    fieldFocused = true
                    NSApp.orderFrontCharacterPalette(nil)
                }
                .labelStyle(.iconOnly)
                .help("Show the Emoji & Symbols viewer")
            }
            .padding(10)

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 40, maximum: 48), spacing: 4)], spacing: 4) {
                    ForEach(Self.emoji, id: \.self) { emoji in
                        let isSelected = icon == .emoji(emoji)
                        Button {
                            icon = .emoji(emoji)
                        } label: {
                            Text(emoji)
                                .font(.system(size: 24))
                                .frame(width: 40, height: 40)
                                .background(isSelected ? Color.accentColor.opacity(0.22) : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(emoji)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
        }
        .onChange(of: typed) { _, newValue in
            guard let first = newValue.trimmingCharacters(in: .whitespacesAndNewlines).first else { return }
            icon = .emoji(String(first))
            typed = ""
        }
    }
}

// MARK: - App icon

private struct AppIconTab: View {
    @Binding var icon: IconSpec?

    private var selectedBundleID: String? {
        if case .app(let bundleID) = icon { return bundleID }
        return nil
    }

    var body: some View {
        AppPickerView(selectedBundleID: selectedBundleID) { app in
            icon = .app(bundleID: app.bundleID)
        }
    }
}

// MARK: - Image file

private struct ImageIconTab: View {
    @Binding var icon: IconSpec?
    @ViewState private var isTargeted = false
    @ViewState private var failure: String?

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator), style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                    .background(isTargeted ? Color.accentColor.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                if case .image = icon {
                    IconView(spec: icon, size: 96)
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 30))
                            .foregroundStyle(.secondary)
                        Text("Drop an image here")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 180, height: 150)
            .dropDestination(for: URL.self) { urls, _ in
                isTargeted = false
                if let url = urls.first { load(url) }
            }
            .onDropSessionUpdated { drop in
                switch drop.phase {
                case .entering, .active: isTargeted = true
                default: isTargeted = false
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(icon.isImage ? "Custom image" : "Image drop area")

            Button("Choose Image…") {
                Task { @MainActor in
                    if let url = await EditorOpenPanel.chooseImage() { load(url) }
                }
            }

            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Text("PNG, JPEG, HEIC, PDF… scaled to 256 × 256 and stored in your configuration.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
        }
        .padding()
    }

    private func load(_ url: URL) {
        guard let data = IconSpec.pngData(fromImageAt: url) else {
            failure = "That file isn't an image Halo can read."
            Log.app.error("Icon image unreadable: \(url.lastPathComponent, privacy: .public)")
            return
        }
        failure = nil
        icon = .image(png: data)
    }
}

private extension Optional where Wrapped == IconSpec {
    var isImage: Bool {
        if case .image = self { return true }
        return false
    }
}

/// A compact search field for pickers.
struct PickerSearchField: View {
    let prompt: String
    @Binding var text: String
    /// Optional focus binding for the text field.
    var isFocused: FocusState<Bool>.Binding?

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            field
                .textFieldStyle(.plain)
                .accessibilityLabel(prompt)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.separator))
    }
}

private extension PickerSearchField {
    @ViewBuilder
    var field: some View {
        if let isFocused {
            TextField(prompt, text: $text).focused(isFocused)
        } else {
            TextField(prompt, text: $text)
        }
    }
}
