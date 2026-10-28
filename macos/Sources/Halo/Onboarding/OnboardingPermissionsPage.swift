import HaloCore
import SwiftUI

/// Step 3: a priming screen for the permissions some actions need, with live status. Nothing
/// here is required to continue.
struct OnboardingPermissionsPage: View {
    var body: some View {
        VStack(spacing: 20) {
            OnboardingHeader(
                symbol: "lock.shield",
                title: "Permissions",
                subtitle: "The ring itself needs no permissions. Some actions, like sending keyboard shortcuts, need your OK first."
            )
            VStack(spacing: 12) {
                OnboardingPermissionRow(permission: .accessibility, isOptional: false)
            }
            Text("Automation is requested the first time a script or Dark Mode action runs. You can change all of these later in Halo Settings › Permissions.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .task { await keepStatusFresh() }
    }

    /// Re-checks every second while the page is open, so a grant made in System Settings shows
    /// up without coming back to Halo first.
    private func keepStatusFresh() async {
        while !Task.isCancelled {
            PermissionCenter.shared.refresh()
            try? await Task.sleep(for: .seconds(1))
        }
    }
}

/// One permission: what it's for, whether it's granted, and a button to grant it.
struct OnboardingPermissionRow: View {
    let permission: Permission
    let isOptional: Bool

    /// Set once the user asked for the permission, to explain where to switch it on.
    @ViewState private var didRequest = false

    var body: some View {
        let title = PermissionCenter.title(permission)
        let isGranted = PermissionCenter.shared.status(permission) == .granted
        // Asked before and refused: usually a stale grant for an earlier build.
        let isRefused = PermissionCenter.shared.status(permission) == .denied
        HStack(spacing: 14) {
            Image(systemName: PermissionCenter.symbol(permission))
                .font(.system(size: 20, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .frame(width: 40, height: 40)
                .background(.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title).font(.headline)
                    if isOptional {
                        Text("Optional")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.fill.tertiary, in: Capsule())
                    }
                }
                Text(PermissionCenter.reason(permission))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if (didRequest || isRefused), !isGranted {
                    Text("Turn on Halo in System Settings › Privacy & Security › \(title). If it already looks on, click Fix Access: macOS is holding on to an older copy of Halo. This page updates by itself.")
                        .font(.callout)
                        .foregroundStyle(.tint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            if isGranted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.green)
            } else {
                Button(isRefused ? "Fix Access…" : "Grant Access…") {
                    didRequest = true
                    PermissionCenter.shared.request(permission)
                }
                .accessibilityLabel("\(isRefused ? "Fix" : "Grant") \(title) access")
            }
        }
        .onboardingCard()
        .accessibilityElement(children: .contain)
    }
}
