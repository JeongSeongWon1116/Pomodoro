// File: PomodoroApp.swift
// Description: 앱의 메인 진입점입니다.
// AppDelegate와 WindowGroup을 사용하여 앱의 생명주기와 UI를 관리합니다.

import SwiftUI
import SwiftData

@main
struct PomodoroApp: App {
    private let container = DataController.shared.container
    @StateObject private var viewModel: PomodoroViewModel
    private let notificationDelegate = NotificationDelegate()

    var body: some Scene {
        MenuBarExtra {
            SettingsView()
                .environmentObject(viewModel)
        } label: {
            StatusBarView(
                emoji: viewModel.currentState.emoji,
                timerState: viewModel.timerState,
                progress: viewModel.progress,
                color: viewModel.currentState.color,
                timeRemainingString: viewModel.timeRemainingString
            )
        }
        .menuBarExtraStyle(.window)
        .modelContainer(container)

        Window("집중 기록", id: "log-window") {
            LogView()
        }
        .modelContainer(container)
    }

    init() {
        let modelContext = container.mainContext
        let viewModel = PomodoroViewModel(modelContext: modelContext)
        _viewModel = StateObject(wrappedValue: viewModel)
        UNUserNotificationCenter.current().delegate = notificationDelegate
        Task {
            await viewModel.requestNotificationPermission()
        }
    }
}
