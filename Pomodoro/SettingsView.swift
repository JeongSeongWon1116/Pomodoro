// File: SettingsView.swift
// Description: 팝오버에 표시될 설정 및 제어 UI입니다.

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var viewModel: PomodoroViewModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 16) {
            Text("뽀모도로 타이머")
                .font(.title2).fontWeight(.bold)
            
            Text("\(viewModel.currentState.description): \(viewModel.timeRemainingString)")
                .font(.subheadline).foregroundColor(.secondary)
                .padding(.bottom, 4)

            Button(action: {
                switch viewModel.timerState {
                case .idle: viewModel.startFocusSession()
                case .paused: viewModel.resumeTimer()
                case .running: viewModel.pauseTimer()
                }
            }) {
                Text(buttonTitle)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .buttonStyle(.plain)

            HStack {
                Button("건너뛰기") { viewModel.skipToNextSession() }
                    .disabled(viewModel.timerState == .idle)
                Spacer()
                Button("초기화") { viewModel.resetToIdle() }
                    .disabled(viewModel.timerState == .idle)
            }
            .padding(.horizontal)

            Divider().padding(.vertical, 8)

            VStack(alignment: .leading, spacing: 12) {
                SettingRow(label: "집중 시간", value: $viewModel.focusDurationInMinutes)
                SettingRow(label: "짧은 휴식", value: $viewModel.shortBreakDurationInMinutes)
                SettingRow(label: "긴 휴식", value: $viewModel.longBreakDurationInMinutes)
            }
            .disabled(viewModel.timerState != .idle)

            Spacer()

            if !viewModel.hasNotificationPermission {
                Button(action: {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                        openURL(url)
                    }
                }) {
                    HStack {
                        Image(systemName: "bell.badge.fill")
                        Text("알림 설정 열기")
                    }
                }
                .tint(.orange)
                .padding(.bottom, 8)
            }

            HStack {
                Button("로그 보기") {
                    appDelegate?.showLogWindow()
                    // DIAGNOSTIC: Temporarily disable popover closing to avoid interference.
                    // appDelegate?.togglePopover(nil)
                }
                Spacer()
                Button("종료") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding()
        .frame(width: 260, height: 380)
    }
    
    private var buttonTitle: String {
        switch viewModel.timerState {
        case .running: "일시정지"
        case .paused: "재개"
        case .idle: "시작"
        }
    }
    
    // AppDelegate에 접근하기 위한 트릭
    private var appDelegate: AppDelegate? {
        NSApp.delegate as? AppDelegate
    }
}

struct SettingRow: View {
    let label: String
    @Binding var value: Int

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Stepper("\(value) 분", value: $value, in: 1...60)
        }
    }
}
