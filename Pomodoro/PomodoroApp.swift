// File: PomodoroApp.swift
// Description: 앱의 메인 진입점입니다.
// AppDelegate와 WindowGroup을 사용하여 앱의 생명주기와 UI를 관리합니다.

import SwiftUI
import SwiftData

@main
struct PomodoroApp: App {
    // AppKit의 생명주기를 관리하기 위해 AppDelegate를 사용합니다.
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // DataController 싱글턴으로부터 공유 ModelContainer를 가져옵니다.
    private let container = DataController.shared.container

    var body: some Scene {
        // Settings Scene to keep the app menu valid.
        Settings {
            EmptyView()
        }
    }

    init() {
        // Pass the ModelContainer to the AppDelegate.
        appDelegate.container = container
    }
}
