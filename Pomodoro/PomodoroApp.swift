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
        // **FIX**: 이 WindowGroup은 앱의 창 관리 시스템을 초기화하기 위해 필요합니다.
        // 직접 사용되지는 않지만, 이 Scene이 없으면 프로그래밍 방식으로 생성된 AppKit 창이
        // 표시되지 않는 문제가 발생합니다.
        WindowGroup {
            EmptyView()
        }
    }

    init() {
        // AppDelegate에 ModelContainer를 전달합니다.
        appDelegate.container = container
    }
}
