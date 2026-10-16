// File: PreferencesView.swift
// Description: 타이머, 알림, Obsidian 연동, 일반 설정을 모아 둔 설정 창입니다.

import SwiftUI
import AppKit
import UserNotifications

struct PreferencesView: View {
    var body: some View {
        TabView {
            TimerSettingsTab()
                .tabItem { Label("Timer", systemImage: "timer") }
            NotificationSettingsTab()
                .tabItem { Label("Notifications", systemImage: "bell") }
            ObsidianSettingsTab()
                .tabItem { Label("Obsidian", systemImage: "doc.text") }
            ShortcutSettingsTab()
                .tabItem { Label("Shortcuts", systemImage: "square.2.layers.3d") }
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 440, height: 340)
    }
}

// MARK: - 타이머

struct TimerSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("Session lengths") {
                Stepper("Focus: \(settings.focusDurationInMinutes.formatted()) min",
                        value: $settings.focusDurationInMinutes, in: 1...120)
                Stepper("Short break: \(settings.shortBreakDurationInMinutes.formatted()) min",
                        value: $settings.shortBreakDurationInMinutes, in: 1...60)
                Stepper("Long break: \(settings.longBreakDurationInMinutes.formatted()) min",
                        value: $settings.longBreakDurationInMinutes, in: 1...60)
                Stepper("Long break every \(settings.longBreakInterval.formatted()) focus sessions",
                        value: $settings.longBreakInterval, in: 2...10)
            }
            Section("Session transitions") {
                Toggle("Transition support (task and reward notes, a choice after focus)", isOn: $settings.transitionManagementEnabled)
                Toggle("Start breaks automatically after focus", isOn: $settings.autoStartBreaks)
                Toggle("Start focus automatically after breaks", isOn: $settings.autoStartFocus)
                Text("With transition support on, a completed focus session waits for you to choose a break or 10 more minutes in the menu bar. Automatic breaks apply only to skipped focus sessions. Turning it off hides task and reward fields and the choice screen. With automatic starts off, each session waits for you to start it from the menu bar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if settings.transitionManagementEnabled {
                RewardListSettings(store: settings.rewardList)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 알림

struct NotificationSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.openURL) private var openURL
    @State private var hasNotificationPermission = true

    var body: some View {
        Form {
            Section("Notification sound") {
                Picker("Session end sound", selection: $settings.notificationSoundName) {
                    Text("None").tag(AppSettings.soundOff)
                    Divider()
                    ForEach(AppSettings.availableSounds, id: \.self) { sound in
                        Text(sound).tag(sound)
                    }
                }
                .onChange(of: settings.notificationSoundName) { _, newValue in
                    guard newValue != AppSettings.soundOff else { return }
                    NSSound(named: newValue)?.play()
                }
                Button("Preview sound") {
                    guard settings.notificationSoundName != AppSettings.soundOff else { return }
                    NSSound(named: settings.notificationSoundName)?.play()
                }
                .disabled(settings.notificationSoundName == AppSettings.soundOff)
            }
            if !hasNotificationPermission {
                Section {
                    HStack {
                        Image(systemName: "bell.badge.fill")
                            .foregroundStyle(.orange)
                        Text("Allow notifications in System Settings to receive banners.")
                            .font(.caption)
                        Spacer()
                        Button("Open notification settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                                openURL(url)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task {
            let notificationSettings = await UNUserNotificationCenter.current().notificationSettings()
            hasNotificationPermission = (notificationSettings.authorizationStatus == .authorized)
        }
    }
}

// MARK: - Obsidian

struct ObsidianSettingsTab: View {
    @ObservedObject private var obsidian = ObsidianExporter.shared

    var body: some View {
        Form {
            Section("Daily notes") {
                Toggle("Write to daily notes when sessions end", isOn: $obsidian.isEnabled)
                if obsidian.isEnabled {
                    HStack {
                        Image(systemName: obsidian.isFolderSelected ? "folder.fill" : "folder.badge.questionmark")
                            .foregroundStyle(obsidian.isFolderSelected ? Color.accentColor : .orange)
                        Text(obsidian.folderName ?? String(localized: "No folder selected"))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Button("Choose folder") { obsidian.chooseFolder() }
                    }
                }
            }
            Section {
                Text("Session records and daily totals are added to the \"\(ObsidianExporter.sectionHeading)\" section of daily notes (yyyy-MM-dd.md). The rest of each note stays as it is.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 단축어

struct ShortcutSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("Shortcuts for focus") {
                shortcutRow(String(localized: "When focus starts"), name: $settings.focusStartShortcut)
                shortcutRow(String(localized: "When focus ends"), name: $settings.focusEndShortcut)
            }
            Section {
                Text("Enter the exact names from the Shortcuts app, such as shortcuts that turn Do Not Disturb on and off. Leave a field empty to skip it. Extending focus runs the start shortcut again. Skipping, resetting, or quitting focus also runs the end shortcut.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func shortcutRow(_ title: String, name: Binding<String>) -> some View {
        LabeledContent(title) {
            TextField(title, text: name, prompt: Text("Shortcut name"))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .frame(width: 170)
            Button("Try running") { URLShortcutRunner().run(named: name.wrappedValue) }
                .disabled(name.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}

// MARK: - 일반

struct GeneralSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var updates = UpdateController.shared

    private var versionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }

    private var lastCheckText: String {
        updates.lastCheckDate?.formatted(date: .abbreviated, time: .shortened) ?? String(localized: "Not yet")
    }

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                Toggle("Show remaining time in the menu bar", isOn: $settings.showTimeInMenuBar)
            }
            UpdateSettingsSection(
                disabledReason: updates.statusText,
                automaticallyChecks: $updates.automaticallyChecks,
                lastCheckText: lastCheckText,
                availableVersion: updates.availableVersion,
                pendingVersion: updates.pendingVersion,
                canInstallNow: updates.canInstallPendingUpdate,
                installing: updates.installInProgress,
                canCheckNow: updates.canCheckForUpdates,
                checkNow: { updates.checkForUpdates() },
                installNow: { updates.installPendingUpdateNow() }
            )
            Section("About") {
                LabeledContent("Version", value: versionString)
                Link("View on GitHub", destination: URL(string: "https://github.com/jeongseongwon1116/pomodoro")!)
            }
        }
        .formStyle(.grouped)
    }
}

/// 설정 > 일반의 "업데이트" 묶음. 상태를 값으로 받아, 업데이터 없이도 그려 볼 수 있습니다.
struct UpdateSettingsSection: View {
    /// 업데이트를 쓰지 않는 빌드이면 그 이유, 쓰고 있으면 nil
    let disabledReason: String?
    @Binding var automaticallyChecks: Bool
    let lastCheckText: String
    /// 찾았지만 곧바로 설치할 수 없는 새 버전 (Sparkle 의 안내 창에서 이어 가는 업데이트)
    let availableVersion: String?
    /// 받아 두고 설치를 기다리는 버전
    let pendingVersion: String?
    let canInstallNow: Bool
    /// 받아 둔 업데이트의 설치를 시작해 앱이 꺼지기를 기다리는 중인지
    let installing: Bool
    let canCheckNow: Bool
    let checkNow: () -> Void
    let installNow: () -> Void

    var body: some View {
        Section("Updates") {
            if let disabledReason {
                Text("Automatic updates are unavailable — \(disabledReason).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Toggle("Check for updates automatically", isOn: $automaticallyChecks)
                LabeledContent("Last checked", value: lastCheckText)
                if let pendingVersion {
                    LabeledContent("Downloaded version \(pendingVersion)") {
                        Button(installing ? String(localized: "Installing…") : String(localized: "Install and reopen now"), action: installNow)
                            .disabled(!canInstallNow)
                    }
                } else {
                    if let availableVersion {
                        Text("Version \(availableVersion) is available.")
                    }
                    Button("Check now", action: checkNow)
                        .disabled(!canCheckNow)
                }
                Text(Self.caption(hasPending: pendingVersion != nil, automaticallyChecks: automaticallyChecks, installing: installing))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 아래 설명 한 줄. 지금 설정에서 실제로 일어나는 일만 적습니다.
    nonisolated static func caption(hasPending: Bool, automaticallyChecks: Bool, installing: Bool = false, locale: Locale = .current) -> String {
        if hasPending {
            if installing { return String(localized: "Installation has started. The app will close and reopen shortly.", bundle: AppLocalization.bundle(for: locale), locale: locale) }
            return String(localized: "A new version is downloaded. Use the button above or Update in the menu bar popover to install and reopen. It also installs when you quit. Further checks wait until installation.", bundle: AppLocalization.bundle(for: locale), locale: locale)
        }
        if !automaticallyChecks {
            return String(localized: "Automatic checks are off. Updates are checked only when you choose Check now.", bundle: AppLocalization.bundle(for: locale), locale: locale)
        }
        return String(localized: "New versions are downloaded and shown as a dot on the menu bar icon. Choose Update to install and reopen. A downloaded update also installs when you quit.", bundle: AppLocalization.bundle(for: locale), locale: locale)
    }
}
