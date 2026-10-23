import AppKit
import ServiceManagement
import SmoothScrollCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    static let width: CGFloat = 460
    static let idealHeight: CGFloat = 760

    @Bindable var settings: Settings
    var openAccessibilitySettings: () -> Void

    // No @State: in the macOS 27 SDK it is a macro whose plugin ships only
    // with Xcode, and this project builds with Command Line Tools alone.
    // Transient UI state lives on `settings` instead.

    var body: some View {
        Form {
            Section {
                if !settings.accessGranted {
                    LabeledContent {
                        Button("Открыть настройки…", action: openAccessibilitySettings)
                    } label: {
                        Label("Нет доступа «Универсальный доступ»", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
                Toggle("Плавная прокрутка", isOn: $settings.enabled)
                Toggle("Запускать при входе в систему", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { setLaunchAtLogin($0) }
                ))
                if let loginError = settings.loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }

            Section("Скорость") {
                Slider(value: $settings.pixelsPerNotch, in: Settings.Range.pixelsPerNotch, step: Settings.Range.step) {
                    Text("Шаг")
                } minimumValueLabel: {
                    Image(systemName: "tortoise")
                } maximumValueLabel: {
                    Image(systemName: "hare")
                }
                presetRow(
                    value: "\(Int(settings.pixelsPerNotch)) px за щелчок",
                    presets: SpeedPreset.allCases.map { ($0.title, $0.pixelsPerNotch) },
                    current: settings.pixelsPerNotch
                ) { settings.pixelsPerNotch = $0 }
            }

            Section("Плавность") {
                Slider(value: $settings.smoothingMs, in: Settings.Range.smoothingMs, step: Settings.Range.step) {
                    Text("Длительность")
                } minimumValueLabel: {
                    Text("резко").font(.caption)
                } maximumValueLabel: {
                    Text("мягко").font(.caption)
                }
                presetRow(
                    value: "\(Int(settings.smoothingMs)) мс",
                    presets: SmoothnessPreset.allCases.map { ($0.title, $0.smoothing * 1000) },
                    current: settings.smoothingMs
                ) { settings.smoothingMs = $0 }
            }

            Section {
                Toggle("Ускорение при быстрой прокрутке", isOn: $settings.accelerate)
                LabeledContent("Сила ускорения") {
                    Slider(value: $settings.acceleration, in: 0.1...1, step: 0.05)
                        .frame(width: 220)
                }
                .disabled(!settings.accelerate)
                Toggle(isOn: $settings.reverse) {
                    Text("Обратное направление")
                    Text("Только для колёсика мыши, трекпад не меняется")
                }
                Toggle(isOn: $settings.stopOnWindowChange) {
                    Text("Останавливать при переходе в другое окно")
                    Text(settings.stopOnWindowChange
                         ? "Если увести курсор во время прокрутки, она сразу прекратится"
                         : "Остаток прокрутки уйдёт в окно под курсором")
                }
            }

            Section {
                Toggle(isOn: $settings.limitRate) {
                    Text("Ограничить частоту щелчков")
                    Text("Для колёсика со свободным ходом: лишние щелчки в потоке отбрасываются")
                }
                LabeledContent("Не чаще чем раз в") {
                    HStack {
                        Slider(value: $settings.minNotchMs, in: Settings.Range.minNotchMs, step: Settings.Range.step)
                            .frame(width: 160)
                        Text("\(Int(settings.minNotchMs)) мс").monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                .disabled(!settings.limitRate)
            }

            Section {
                ForEach($settings.profiles) { $profile in
                    DisclosureGroup(isExpanded: expansion(profile.id)) {
                        ProfileEditor(profile: $profile) { settings.removeProfile(profile.id) }
                    } label: {
                        HStack {
                            Text(profile.name)
                            Spacer()
                            if profile.excluded {
                                Text("отключено").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                HStack {
                    Button("Добавить приложение…", action: pickApplication)
                    if let id = settings.frontmostBundleID, let name = settings.frontmostName,
                       settings.profile(for: id) == nil {
                        Button("Добавить «\(name)»") {
                            settings.ensureProfile(bundleID: id, name: name)
                            settings.selectedProfileID = id
                        }
                    }
                }
            } header: {
                Text("Приложения")
            } footer: {
                Text("Профиль включается, когда приложение активно. Можно полностью отключить плавную прокрутку (игры, 3D-редакторы) или задать свои параметры.")
            }

            Section("Проверка — покрутите колёсико здесь") {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(1...200, id: \.self) { i in
                            Text("Строка \(i)")
                                .foregroundStyle(i % 10 == 0 ? .primary : .secondary)
                                .fontWeight(i % 10 == 0 ? .semibold : .regular)
                        }
                    }
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 140)
            }

            Section {
                HStack {
                    Spacer()
                    Button("Сбросить по умолчанию") { settings.resetToDefaults() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: Self.width)
        .frame(minHeight: 320, idealHeight: Self.idealHeight)
        .onAppear { settings.launchAtLogin = SMAppService.mainApp.status == .enabled }
    }

    private func expansion(_ id: String) -> Binding<Bool> {
        Binding(
            get: { settings.selectedProfileID == id },
            set: { open in
                if open { settings.selectedProfileID = id }
                else if settings.selectedProfileID == id { settings.selectedProfileID = nil }
            }
        )
    }

    private func pickApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(filePath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.prompt = "Добавить"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.selectedProfileID = settings.addProfile(appURL: url)
    }

    private func presetRow(
        value: String,
        presets: [(String, Double)],
        current: Double,
        select: @escaping (Double) -> Void
    ) -> some View {
        HStack {
            Text(value).monospacedDigit().foregroundStyle(.secondary)
            Spacer()
            ForEach(presets, id: \.0) { title, preset in
                Button(title) { select(preset) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(abs(current - preset) < 0.5 ? .accentColor : nil)
            }
        }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        let service = SMAppService.mainApp
        do {
            if on { try service.register() } else { try service.unregister() }
            settings.loginError = nil
        } catch {
            settings.loginError = "\(error.localizedDescription) Переместите SmoothScroll.app в «Программы»."
        }
        if on && service.status == .requiresApproval {
            // Registered, but the user has to allow it in System Settings.
            settings.loginError = "Разрешите SmoothScroll в Системных настройках › Основные › Объекты входа."
            SMAppService.openSystemSettingsLoginItems()
        }
        settings.launchAtLogin = service.status == .enabled
    }
}

private extension SpeedPreset {
    var title: String {
        switch self {
        case .slow: "Медл."
        case .normal: "Обычно"
        case .fast: "Быстро"
        case .veryFast: "Оч. быстро"
        }
    }
}

private extension SmoothnessPreset {
    var title: String {
        switch self {
        case .low: "Коротко"
        case .medium: "Средне"
        case .high: "Длинно"
        }
    }
}

/// Editor for one app profile: exclusion switch plus its own scroll parameters.
private struct ProfileEditor: View {
    @Binding var profile: AppProfile
    var onDelete: () -> Void

    var body: some View {
        Toggle("Отключить плавную прокрутку в этом приложении", isOn: $profile.excluded)
        if !profile.excluded {
            LabeledContent("Скорость: \(Int(profile.pixelsPerNotch)) px") {
                Slider(value: $profile.pixelsPerNotch, in: Settings.Range.pixelsPerNotch, step: Settings.Range.step)
                    .frame(width: 200)
            }
            LabeledContent("Плавность: \(Int(profile.smoothingMs)) мс") {
                Slider(value: $profile.smoothingMs, in: Settings.Range.smoothingMs, step: Settings.Range.step)
                    .frame(width: 200)
            }
            Toggle("Ускорение", isOn: $profile.accelerate)
            Toggle("Обратное направление", isOn: $profile.reverse)
            Toggle("Ограничить частоту щелчков", isOn: $profile.limitRate)
            if profile.limitRate {
                LabeledContent("Не чаще чем раз в \(Int(profile.minNotchMs)) мс") {
                    Slider(value: $profile.minNotchMs, in: Settings.Range.minNotchMs, step: Settings.Range.step)
                        .frame(width: 200)
                }
            }
        }
        HStack {
            Spacer()
            Button("Удалить профиль", role: .destructive, action: onDelete)
        }
    }
}
