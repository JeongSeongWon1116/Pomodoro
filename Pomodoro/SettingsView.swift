// File: SettingsView.swift
// Description: 팝오버에 표시될 설정 및 제어 UI입니다.

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var viewModel: PomodoroViewModel
    @ObservedObject private var obsidian = ObsidianExporter.shared
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 14) {
            Text("뽀모도로 타이머")
                .font(.title2).fontWeight(.bold)

            Text("\(viewModel.currentState.description): \(viewModel.timeRemainingString)")
                .font(.subheadline).foregroundColor(.secondary)
                .padding(.bottom, 2)

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

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                SettingRow(label: "집중 시간", value: $viewModel.focusDurationInMinutes, unit: "분", range: 1...60)
                SettingRow(label: "짧은 휴식", value: $viewModel.shortBreakDurationInMinutes, unit: "분", range: 1...60)
                SettingRow(label: "긴 휴식", value: $viewModel.longBreakDurationInMinutes, unit: "분", range: 1...60)
                SettingRow(label: "긴 휴식 간격", value: $viewModel.longBreakInterval, unit: "회마다", range: 2...10)
            }
            .disabled(viewModel.timerState != .idle)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: $obsidian.isEnabled) {
                    Text("Obsidian 데일리 노트 기록")
                }
                .toggleStyle(.switch)
                .controlSize(.small)

                if obsidian.isEnabled {
                    HStack {
                        Image(systemName: obsidian.isFolderSelected ? "folder.fill" : "folder.badge.questionmark")
                            .foregroundStyle(obsidian.isFolderSelected ? Color.accentColor : .orange)
                        Text(obsidian.folderName ?? "폴더가 선택되지 않았습니다")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Button("폴더 선택") { obsidian.chooseFolder() }
                            .controlSize(.small)
                    }
                }
            }

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
            }

            HStack {
                Button("로그 보기") {
                    openWindow(id: "log-window")
                    appDelegate?.closePopover()
                }
                Spacer()
                Button("종료") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding()
        .frame(width: 280, height: 500)
    }

    private var buttonTitle: String {
        switch viewModel.timerState {
        case .running: "일시정지"
        case .paused: "재개"
        case .idle: "시작"
        }
    }

    private var appDelegate: AppDelegate? {
        NSApp.delegate as? AppDelegate
    }
}

struct SettingRow: View {
    let label: String
    @Binding var value: Int
    var unit: String = "분"
    var range: ClosedRange<Int> = 1...60

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Stepper("\(value)\(unit)", value: $value, in: range)
        }
    }
}
