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
        // **FIX**: Window를 사용하여 단일 윈도우만 열리도록 합니다.
        // WindowGroup은 여러 윈도우를 허용하지만, Window는 단일 인스턴스만 허용합니다.
        Window("집중 기록", id: "log-window") {
            LogView()
        }
        .modelContainer(container) // 전체 뷰 계층에 공유 ModelContainer를 주입합니다.
    }

    init() {
        // AppDelegate가 초기화된 후, 앱의 메인 ModelContext를 전달합니다.
        appDelegate.modelContext = container.mainContext
    }
}
