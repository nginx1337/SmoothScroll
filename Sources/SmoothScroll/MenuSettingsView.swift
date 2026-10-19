import AppKit
import SwiftUI

/// Compact speed / smoothness sliders embedded in the menu bar menu.
/// Edits apply live through `Settings`, same as the settings window.
struct MenuSettingsView: View {
    @Bindable var settings: Settings

    static let width: CGFloat = 270

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            slider("Скорость", value: $settings.pixelsPerNotch, in: Settings.Range.pixelsPerNotch, step: Settings.Range.step,
                   label: "\(Int(settings.pixelsPerNotch)) px")
            slider("Плавность", value: $settings.smoothingMs, in: Settings.Range.smoothingMs, step: Settings.Range.step,
                   label: "\(Int(settings.smoothingMs)) мс")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(width: Self.width, alignment: .leading)
        .disabled(!settings.enabled)
    }

    private func slider(
        _ title: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double, label: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(label).monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.system(size: 12))
            // Round manually: `Slider(step:)` draws a tick mark per step,
            // which is noisy at this size.
            Slider(value: Binding(
                get: { value.wrappedValue },
                set: { value.wrappedValue = ($0 / step).rounded() * step }
            ), in: range)
                .controlSize(.small)
        }
    }

    /// Menu item hosting the view, sized to fit.
    @MainActor
    static func menuItem(settings: Settings) -> NSMenuItem {
        let host = NSHostingView(rootView: MenuSettingsView(settings: settings))
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        let item = NSMenuItem()
        item.view = host
        return item
    }
}
