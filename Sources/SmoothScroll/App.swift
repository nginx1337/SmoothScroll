import AppKit
import ApplicationServices
import SmoothScrollCore
import SwiftUI

@main
enum SmoothScrollApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = Settings()
    private let interceptor = ScrollInterceptor()
    private var statusItem: NSStatusItem!
    private var accessTimer: Timer?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings.onChange = { [weak self] in self?.applySettings() }
        applySettings()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateIcon()

        refreshAccess(prompt: true)
        // Access can be granted or revoked at any time (also implicitly, when
        // a rebuild changes the ad-hoc signature), so keep checking.
        accessTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAccess(prompt: false) }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        interceptor.stop()
    }

    /// Opening the app again (Finder, Spotlight) while it runs shows settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    /// Starts the tap once Accessibility access is granted and stops it if
    /// access is revoked, keeping the icon and settings window truthful.
    private func refreshAccess(prompt: Bool) {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if trusted && !interceptor.isRunning {
            interceptor.start()
        } else if !trusted && interceptor.isRunning {
            interceptor.stop()
        }
        if settings.accessGranted != interceptor.isRunning {
            settings.accessGranted = interceptor.isRunning
        }
        updateIcon()
    }

    private func applySettings() {
        interceptor.config = settings.scrollConfig
        interceptor.isEnabled = settings.enabled
        interceptor.stopsOnWindowChange = settings.stopOnWindowChange
        updateIcon()
    }

    private func updateIcon() {
        guard let button = statusItem?.button else { return }
        if interceptor.isRunning {
            button.image = settings.enabled ? StatusIcon.on : StatusIcon.off
        } else {
            // No Accessibility access: a standard warning sign reads clearer.
            let image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "SmoothScroll")
            image?.isTemplate = true
            button.image = image
        }
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if !interceptor.isRunning {
            let warning = NSMenuItem(title: "Нужен доступ «Универсальный доступ»", action: nil, keyEquivalent: "")
            warning.isEnabled = false
            menu.addItem(warning)
            menu.addItem(item("Открыть настройки доступа…", #selector(openAccessibilitySettings)))
            menu.addItem(.separator())
        }

        let toggle = item("Плавная прокрутка", #selector(toggleEnabled))
        toggle.state = settings.enabled ? .on : .off
        menu.addItem(toggle)
        menu.addItem(.separator())
        menu.addItem(MenuSettingsView.menuItem(settings: settings))
        let accelerate = item("Ускорение при быстрой прокрутке", #selector(toggleAccelerate))
        accelerate.state = settings.accelerate ? .on : .off
        menu.addItem(accelerate)
        let reverse = item("Обратное направление", #selector(toggleReverse))
        reverse.state = settings.reverse ? .on : .off
        menu.addItem(reverse)
        let stopOnWindow = item("Останавливать при переходе в другое окно", #selector(toggleStopOnWindowChange))
        stopOnWindow.state = settings.stopOnWindowChange ? .on : .off
        menu.addItem(stopOnWindow)
        menu.addItem(.separator())
        menu.addItem(item("Все настройки…", #selector(showSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(item("Выйти из SmoothScroll", #selector(NSApplication.terminate(_:)), key: "q", target: NSApp))
    }

    private func item(_ title: String, _ action: Selector, key: String = "", target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target ?? self
        return item
    }

    @objc private func toggleEnabled() {
        settings.enabled.toggle()
    }

    @objc private func toggleAccelerate() {
        settings.accelerate.toggle()
    }

    @objc private func toggleReverse() {
        settings.reverse.toggle()
    }

    @objc private func toggleStopOnWindowChange() {
        settings.stopOnWindowChange.toggle()
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            let view = SettingsView(settings: settings) { [weak self] in self?.openAccessibilitySettings() }
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Настройки SmoothScroll"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            // The form scrolls, so fit the window to the screen it opens on.
            let available = (NSScreen.main?.visibleFrame.height ?? 800) - 60
            window.setContentSize(NSSize(width: SettingsView.width, height: min(SettingsView.idealHeight, available)))
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
