// File: AppSettings.swift
// Description: 모든 사용자 설정을 한곳에서 관리하는 싱글턴입니다.
// 팝오버, 설정 창, ViewModel이 같은 인스턴스를 관찰하여 항상 동기화됩니다.

import SwiftUI
import Combine
import ServiceManagement

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    static let soundOff = "없음"
    // NSSound(named:)로 재생 가능한 macOS 시스템 알림음 목록
    static let availableSounds = [
        "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero",
        "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"
    ]

    @Published var focusDurationInMinutes: Int {
        didSet { UserDefaults.standard.set(focusDurationInMinutes, forKey: "focusDuration") }
    }
    @Published var shortBreakDurationInMinutes: Int {
        didSet { UserDefaults.standard.set(shortBreakDurationInMinutes, forKey: "shortBreakDuration") }
    }
    @Published var longBreakDurationInMinutes: Int {
        didSet { UserDefaults.standard.set(longBreakDurationInMinutes, forKey: "longBreakDuration") }
    }
    @Published var longBreakInterval: Int {
        didSet { UserDefaults.standard.set(longBreakInterval, forKey: "longBreakInterval") }
    }

    /// 집중이 끝났을 때 휴식을 자동으로 시작할지 여부
    @Published var autoStartBreaks: Bool {
        didSet { UserDefaults.standard.set(autoStartBreaks, forKey: "autoStartBreaks") }
    }
    /// 휴식이 끝났을 때 집중을 자동으로 시작할지 여부
    @Published var autoStartFocus: Bool {
        didSet { UserDefaults.standard.set(autoStartFocus, forKey: "autoStartFocus") }
    }

    @Published var notificationSoundName: String {
        didSet { UserDefaults.standard.set(notificationSoundName, forKey: "notificationSound") }
    }

    /// 메뉴 바에 남은 시간을 텍스트로 표시할지 여부
    @Published var showTimeInMenuBar: Bool {
        didSet { UserDefaults.standard.set(showTimeInMenuBar, forKey: "showTimeInMenuBar") }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != (SMAppService.mainApp.status == .enabled) else { return }
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("로그인 시 자동 실행 설정 실패: \(error)")
            }
        }
    }

    private init() {
        let defaults = UserDefaults.standard
        self.focusDurationInMinutes = (defaults.object(forKey: "focusDuration") as? Int) ?? 25
        self.shortBreakDurationInMinutes = (defaults.object(forKey: "shortBreakDuration") as? Int) ?? 5
        self.longBreakDurationInMinutes = (defaults.object(forKey: "longBreakDuration") as? Int) ?? 15
        self.longBreakInterval = (defaults.object(forKey: "longBreakInterval") as? Int) ?? 4
        self.autoStartBreaks = (defaults.object(forKey: "autoStartBreaks") as? Bool) ?? true
        self.autoStartFocus = (defaults.object(forKey: "autoStartFocus") as? Bool) ?? true
        self.notificationSoundName = defaults.string(forKey: "notificationSound") ?? "Glass"
        self.showTimeInMenuBar = (defaults.object(forKey: "showTimeInMenuBar") as? Bool) ?? true
        self.launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
