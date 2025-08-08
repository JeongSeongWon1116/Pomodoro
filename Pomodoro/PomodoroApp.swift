// File: PomodoroApp.swift
// Description: 앱의 메인 진입점입니다.
// AppDelegate와 WindowGroup을 사용하여 앱의 생명주기와 UI를 관리합니다.

import SwiftUI
import SwiftData

@main
struct PomodoroApp: App {
    // DataController 싱글턴으로부터 공유 ModelContainer를 가져옵니다.
    private let container = DataController.shared.container
    // ViewModel을 앱 생명주기에 맞게 상태로 관리합니다.
    @State private var viewModel: PomodoroViewModel

    var body: some Scene {
        // **FIX**: AppDelegate 대신 MenuBarExtra를 사용하여 앱의 UI를 구성합니다.
        // 이는 순수 SwiftUI 접근 방식으로, 더 안정적이고 예측 가능합니다.
        MenuBarExtra {
            SettingsView()
                .environmentObject(viewModel)
        } label: {
            StatusBarView()
                .environmentObject(viewModel)
        }
        .menuBarExtraStyle(.window) // .window 스타일은 popover UI를 제공합니다.
        .modelContainer(container)

        // **FIX**: 로그 창을 위해 WindowGroup 대신 Window를 사용합니다.
        // 이렇게 하면 한 번에 하나의 로그 창만 열 수 있습니다.
        Window("집중 기록", id: "log-window") {
            LogView()
        }
    }

    init() {
        // ViewModel을 초기화합니다. AppDelegate가 없으므로 여기서 직접 생성합니다.
        let modelContext = container.mainContext
        _viewModel = State(initialValue: PomodoroViewModel(modelContext: modelContext))
    }
}
