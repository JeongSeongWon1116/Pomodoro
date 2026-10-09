// File: PreferencesView.swift
// Description: 타이머, 알림, Obsidian 연동, 일반 설정을 모아 둔 설정 창입니다.

import SwiftUI
import AppKit
import UserNotifications

struct PreferencesView: View {
    var body: some View {
        TabView {
            TimerSettingsTab()
                .tabItem { Label("타이머", systemImage: "timer") }
            NotificationSettingsTab()
                .tabItem { Label("알림", systemImage: "bell") }
            ObsidianSettingsTab()
                .tabItem { Label("Obsidian", systemImage: "doc.text") }
            ShortcutSettingsTab()
                .tabItem { Label("단축어", systemImage: "square.2.layers.3d") }
            GeneralSettingsTab()
                .tabItem { Label("일반", systemImage: "gearshape") }
        }
        .frame(width: 440, height: 340)
    }
}

// MARK: - 타이머

struct TimerSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("세션 길이") {
                Stepper("집중 시간: \(settings.focusDurationInMinutes)분",
                        value: $settings.focusDurationInMinutes, in: 1...120)
                Stepper("짧은 휴식: \(settings.shortBreakDurationInMinutes)분",
                        value: $settings.shortBreakDurationInMinutes, in: 1...60)
                Stepper("긴 휴식: \(settings.longBreakDurationInMinutes)분",
                        value: $settings.longBreakDurationInMinutes, in: 1...60)
                Stepper("긴 휴식 간격: 집중 \(settings.longBreakInterval)회마다",
                        value: $settings.longBreakInterval, in: 2...10)
            }
            Section("세션 전환") {
                Toggle("전환 관리 (할 일·보상 적기, 집중이 끝나면 선택 기다리기)", isOn: $settings.transitionManagementEnabled)
                Toggle("집중이 끝나면 휴식 자동 시작", isOn: $settings.autoStartBreaks)
                Toggle("휴식이 끝나면 집중 자동 시작", isOn: $settings.autoStartFocus)
                Text("전환 관리를 켜면, 끝까지 마친 집중은 저절로 넘어가지 않고 메뉴 바에서 휴식 시작이나 10분 연장을 고를 때까지 기다립니다(휴식 자동 시작은 건너뛴 집중에만 적용). 끄면 할 일·보상 칸과 선택 화면이 없어지고 예전처럼 동작합니다. 자동 시작을 끄면 세션이 끝났을 때 대기 상태로 멈추고, 메뉴 바에서 직접 시작할 수 있습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            Section("알림음") {
                Picker("세션 종료 알림음", selection: $settings.notificationSoundName) {
                    Text(AppSettings.soundOff).tag(AppSettings.soundOff)
                    Divider()
                    ForEach(AppSettings.availableSounds, id: \.self) { sound in
                        Text(sound).tag(sound)
                    }
                }
                .onChange(of: settings.notificationSoundName) { _, newValue in
                    guard newValue != AppSettings.soundOff else { return }
                    NSSound(named: newValue)?.play()
                }
                Button("미리 듣기") {
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
                        Text("배너 알림을 받으려면 시스템 설정에서 알림을 허용하세요.")
                            .font(.caption)
                        Spacer()
                        Button("알림 설정 열기") {
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
            Section("데일리 노트 기록") {
                Toggle("세션이 끝나면 데일리 노트에 기록", isOn: $obsidian.isEnabled)
                if obsidian.isEnabled {
                    HStack {
                        Image(systemName: obsidian.isFolderSelected ? "folder.fill" : "folder.badge.questionmark")
                            .foregroundStyle(obsidian.isFolderSelected ? Color.accentColor : .orange)
                        Text(obsidian.folderName ?? "폴더가 선택되지 않았습니다")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Button("폴더 선택") { obsidian.chooseFolder() }
                    }
                }
            }
            Section {
                Text("데일리 노트(yyyy-MM-dd.md)의 \"\(ObsidianExporter.sectionHeading)\" 섹션에 세션 기록과 하루 통계가 자동으로 기록됩니다. 노트의 다른 내용은 건드리지 않습니다.")
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
            Section("집중할 때 실행할 단축어") {
                shortcutRow("집중을 시작할 때", name: $settings.focusStartShortcut)
                shortcutRow("집중이 끝날 때", name: $settings.focusEndShortcut)
            }
            Section {
                Text("단축어 앱에 있는 단축어의 이름을 그대로 적습니다(예: 방해금지 모드를 켜는 단축어와 끄는 단축어). 비워 두면 실행하지 않습니다. 연장하면 시작 단축어를 다시 실행하고, 건너뛰기·초기화·종료로 집중을 그만둘 때도 끝 단축어를 실행합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func shortcutRow(_ title: String, name: Binding<String>) -> some View {
        LabeledContent(title) {
            TextField(title, text: name, prompt: Text("단축어 이름"))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .frame(width: 170)
            Button("실행해 보기") { URLShortcutRunner().run(named: name.wrappedValue) }
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
        updates.lastCheckDate?.formatted(date: .abbreviated, time: .shortened) ?? "아직 없음"
    }

    var body: some View {
        Form {
            Section {
                Toggle("로그인 시 자동 실행", isOn: $settings.launchAtLogin)
                Toggle("메뉴 바에 남은 시간 표시", isOn: $settings.showTimeInMenuBar)
            }
            UpdateSettingsSection(
                disabledReason: updates.statusText,
                automaticallyChecks: $updates.automaticallyChecks,
                automaticallyInstalls: $updates.automaticallyInstalls,
                lastCheckText: lastCheckText,
                availableVersion: updates.availableVersion,
                canCheckNow: updates.canCheckForUpdates,
                checkNow: { updates.checkForUpdates() }
            )
            Section("정보") {
                LabeledContent("버전", value: versionString)
                Link("GitHub에서 보기", destination: URL(string: "https://github.com/jeongseongwon1116/pomodoro")!)
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
    @Binding var automaticallyInstalls: Bool
    let lastCheckText: String
    let availableVersion: String?
    let canCheckNow: Bool
    let checkNow: () -> Void

    var body: some View {
        Section("업데이트") {
            if let disabledReason {
                Text("자동 업데이트를 쓰지 않습니다 — \(disabledReason).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Toggle("자동으로 업데이트 확인", isOn: $automaticallyChecks)
                Toggle("새 버전을 자동으로 받아 설치", isOn: $automaticallyInstalls)
                    .disabled(!automaticallyChecks)
                LabeledContent("마지막 확인", value: lastCheckText)
                if let availableVersion {
                    Text("새 버전 \(availableVersion)이 있습니다.")
                }
                Button("지금 확인", action: checkNow)
                    .disabled(!canCheckNow)
                Text("자동 설치는 타이머가 대기 중이고 창이 모두 닫혀 있을 때 앱을 다시 켜면서 이루어집니다. 그 전에 앱을 끄면 그때 설치됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
