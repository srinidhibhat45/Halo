import AppKit
import HaloCore
import SwiftUI

/// One card per macOS permission: live status, why Halo needs it, which actions use it
/// (in general and in the user's own rings), and how to grant it. Statuses refresh when the
/// pane appears, when Halo becomes active and when a window becomes key.
struct PermissionsPane: View {
    private var center: PermissionCenter { .shared }
    private var model: AppModel { .shared }

    var body: some View {
        let usage = Permission.allCases.reduce(into: [Permission: [String]]()) { result, permission in
            result[permission] = Self.actionTitles(in: model.config, needing: permission)
        }
        Form {
            Section {
                PermissionsSummary(missing: Permission.allCases.filter { usage[$0]?.isEmpty == false && center.status($0) != .granted })
            }
            ForEach(Permission.allCases, id: \.self) { permission in
                Section {
                    PermissionCard(permission: permission, status: center.status(permission), usedInRings: usage[permission] ?? [])
                }
            }
            Section {
                Label {
                    Text("If Halo is switched on in System Settings but still can't act, the copy you're running may have been rebuilt or moved. Turn Halo off and on again in that list, or remove it with − and add it again.")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "wrench.and.screwdriver")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            } header: {
                Text("Troubleshooting")
            }
        }
        .formStyle(.grouped)
        .onAppear { center.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            center.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            center.refresh()
        }
    }

    /// Titles of the actions in the user's rings (all levels, global and app rings) that need
    /// `permission`, without repeats.
    private static func actionTitles(in config: HaloConfig, needing permission: Permission) -> [String] {
        var titles: [String] = []
        var seen = Set<String>()
        func visit(_ ring: Ring) {
            for slot in ring.slots {
                guard let action = slot.action else { continue }
                if case .folder(let inner) = action {
                    visit(inner)
                } else if action.requiredPermissions.contains(permission), seen.insert(slot.displayTitle).inserted {
                    titles.append(slot.displayTitle)
                }
            }
        }
        visit(config.globalRing)
        config.appProfiles.forEach { visit($0.ring) }
        return titles
    }
}

/// "All set" or what's missing, at the top of the pane.
private struct PermissionsSummary: View {
    let missing: [Permission]

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: missing.isEmpty ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                .font(.system(size: 28))
                .foregroundStyle(missing.isEmpty ? Color.green : Color.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(missing.isEmpty ? "Halo has what your rings need" : "Some of your actions need permission")
                    .font(.headline)
                Text(missing.isEmpty
                     ? "Each permission below is needed only by the actions listed with it."
                     : "Allow \(ListFormatter.localizedString(byJoining: missing.map(PermissionCenter.title))) so every action in your rings can run.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct PermissionCard: View {
    let permission: Permission
    let status: PermissionStatus
    /// Titles of the user's actions that need this permission.
    let usedInRings: [String]

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: PermissionCenter.symbol(permission))
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(PermissionCenter.title(permission))
                        .font(.headline)
                    Spacer(minLength: 8)
                    badge
                }
                Text(PermissionCenter.reason(permission))
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("**Used by:** \(neededBy)")
                    Text(ringUsage)
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                buttons
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(PermissionCenter.title(permission)) permission")
    }

    @ViewBuilder
    private var badge: some View {
        switch status {
        case .granted:
            StatusBadge("Allowed", symbol: "checkmark.circle.fill", tone: .positive)
        case .denied:
            StatusBadge("Not Allowed", symbol: "xmark.circle.fill", tone: .negative)
        case .notDetermined:
            StatusBadge(permission == .automation ? "Asks When Needed" : "Not Set Up", symbol: "circle.dashed", tone: .neutral)
        }
    }

    /// Asked before, still refused: usually a stale grant for an earlier build of Halo.
    private var needsRepair: Bool { status == .denied && permission != .automation }

    @ViewBuilder
    private var buttons: some View {
        HStack {
            if status != .granted {
                Button(needsRepair ? "Fix Access…" : "Grant Access…") { PermissionCenter.shared.request(permission) }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("\(needsRepair ? "Fix" : "Grant") \(PermissionCenter.title(permission)) access")
            }
            Button("Open System Settings") { PermissionCenter.shared.openSystemSettings(for: permission) }
                .accessibilityLabel("Open \(PermissionCenter.title(permission)) in System Settings")
        }
        .padding(.top, 2)
        if needsRepair {
            Text("Already switched on in System Settings? macOS can be holding on to an older copy of Halo. Fix Access clears that entry; then switch Halo on once more when macOS asks.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var tint: Color {
        switch permission {
        case .accessibility: .blue
        case .automation: .indigo
        case .screenRecording: .purple
        }
    }

    /// Which kinds of action need the permission.
    private var neededBy: String {
        switch permission {
        case .accessibility:
            "keyboard shortcuts, media and brightness keys, Edit commands, window layouts, text snippets, most System actions, and prompts or Shortcuts that use the selected text."
        case .automation:
            "AppleScripts and the Dark Mode switch. macOS asks the first time one runs."
        case .screenRecording:
            "nothing in Halo today: screenshots use your Mac's own screenshot shortcuts. You can leave it off."
        }
    }

    private var ringUsage: String {
        guard !usedInRings.isEmpty else { return "None of the actions in your rings need it right now." }
        let shown = usedInRings.prefix(4)
        let names = shown.map { "“\($0)”" }.joined(separator: ", ")
        let more = usedInRings.count - shown.count
        let count = usedInRings.count == 1 ? "1 action" : "\(usedInRings.count) actions"
        return "In your rings: \(count) (\(names)\(more > 0 ? " and \(more) more" : ""))."
    }
}
