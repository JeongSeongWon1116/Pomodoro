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
                Toggle("집중이 끝나면 휴식 자동 시작", isOn: $settings.autoStartBreaks)
                Toggle("휴식이 끝나면 집중 자동 시작", isOn: $settings.autoStartFocus)
                Text("끄면 세션이 끝났을 때 대기 상태로 멈추고, 메뉴 바에서 직접 시작할 수 있습니다.")
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

// MARK: - 일반

struct GeneralSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared

    private var versionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                Toggle("로그인 시 자동 실행", isOn: $settings.launchAtLogin)
                Toggle("메뉴 바에 남은 시간 표시", isOn: $settings.showTimeInMenuBar)
            }
            Section("정보") {
                LabeledContent("버전", value: versionString)
                Link("GitHub에서 보기", destination: URL(string: "https://github.com/jeongseongwon1116/pomodoro")!)
            }
        }
        .formStyle(.grouped)
    }
}
