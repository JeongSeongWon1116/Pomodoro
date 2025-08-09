// File: SettingsView.swift
// Description: 팝오버에 표시될 설정 및 제어 UI입니다.

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var viewModel: PomodoroViewModel
    // **FIX**: 'openWindow'를 사용하기 위해 Environment 값을 선언합니다.
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 16) {
            Text("뽀모도로 타이머")
                .font(.title2).fontWeight(.bold)
            
            Text("\(viewModel.currentState.description): \(viewModel.timeRemainingString)")
                .font(.subheadline).foregroundColor(.secondary)

            BatteryProgressBar(progress: viewModel.progress, color: viewModel.currentState.color)
                .frame(height: 14)
                .padding(.horizontal)

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
                    openWindow(id: "log-window")
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
}

struct BatteryProgressBar: View {
    var progress: Double
    var color: Color

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3.5)
                .stroke(Color.primary.opacity(0.8), lineWidth: 1.5)

            GeometryReader { geometry in
                let fillWidth = (geometry.size.width - 3) * CGFloat(progress)
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: fillWidth)
                    .padding(1.5)
            }
        }
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
