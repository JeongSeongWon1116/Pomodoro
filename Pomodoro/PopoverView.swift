// File: PopoverView.swift
// Description: 메뉴 바 아이콘 클릭 시 표시되는 팝오버 UI입니다.
// 타이머 제어에 집중하고, 상세 설정은 별도의 설정 창에서 합니다.

import SwiftUI

struct PopoverView: View {
    @EnvironmentObject var viewModel: PomodoroViewModel
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.openWindow) private var openWindow

    private var isAwaitingChoice: Bool { viewModel.timerState == .awaitingChoice }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: isAwaitingChoice ? "bell.badge" : viewModel.currentState.symbolName)
                    .foregroundStyle(viewModel.currentState.color)
                Text(isAwaitingChoice ? "\(viewModel.currentState.description) 끝" : viewModel.currentState.description)
                    .fontWeight(.semibold)
            }
            .font(.headline)

            Text(viewModel.timeRemainingString)
                .font(.system(size: 44, weight: .light, design: .rounded))
                .monospacedDigit()

            CycleDotsView(
                completed: viewModel.focusSessionsInCurrentCycle,
                total: settings.longBreakInterval
            )

            if settings.transitionManagementEnabled || isAwaitingChoice {
                transitionNotes
            }

            Button(action: primaryAction) {
                Text(buttonTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .buttonStyle(.plain)

            if isAwaitingChoice {
                Button("\(Int(PomodoroViewModel.focusExtension / 60))분 더 집중") { viewModel.extendFocus() }
                    .frame(maxWidth: .infinity)
            }

            HStack {
                Button("건너뛰기") { viewModel.skipToNextSession() }
                    .disabled(viewModel.timerState == .idle || isAwaitingChoice)
                Spacer()
                Button("초기화") { viewModel.resetToIdle() }
                    .disabled(viewModel.timerState == .idle && viewModel.currentState == .idle)
            }
            .padding(.horizontal, 4)

            Divider()

            HStack {
                Button("로그 보기") {
                    viewModel.closePopover()
                    openWindow(id: "log-window")
                }
                Spacer()
                Button {
                    viewModel.closePopover()
                    openWindow(id: "settings-window")
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("설정")
                Spacer()
                Button("종료") {
                    // 진행 중인 세션이 사라지지 않도록 종료 전에 기록합니다.
                    viewModel.logInterruptedSession()
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding()
        // 높이는 내용(할 일·보상 칸, 선택 화면)에 맞춰 달라집니다.
        .frame(width: 260)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// 할 일·보상·다음 시작점. 집중 전과 집중 중에는 적는 칸, 집중이 끝나면 보상과 다음 시작점 칸, 휴식 중에는 읽기만.
    @ViewBuilder
    private var transitionNotes: some View {
        let reward = viewModel.focusReward.trimmingCharacters(in: .whitespacesAndNewlines)
        VStack(alignment: .leading, spacing: 6) {
            if isAwaitingChoice {
                if !reward.isEmpty { NoteLine(label: "보상", text: reward) }
                TextField("다음에 이어서 시작할 자리", text: $viewModel.nextStartingPoint)
                    .textFieldStyle(.roundedBorder)
            } else if viewModel.currentState == .idle || viewModel.currentState == .focus {
                if !viewModel.resumeHint.isEmpty { NoteLine(label: "이어서", text: viewModel.resumeHint) }
                TextField("할 일", text: $viewModel.focusTask)
                    .textFieldStyle(.roundedBorder)
                TextField("끝나면 받을 보상", text: $viewModel.focusReward)
                    .textFieldStyle(.roundedBorder)
            } else {
                if !reward.isEmpty { NoteLine(label: "보상", text: reward) }
                if !viewModel.resumeHint.isEmpty { NoteLine(label: "다음 시작점", text: viewModel.resumeHint) }
            }
        }
    }

    private func primaryAction() {
        switch viewModel.timerState {
        case .idle: viewModel.startFocusSession()
        case .paused: viewModel.resumeTimer()
        case .running: viewModel.pauseTimer()
        case .awaitingChoice: viewModel.startBreakAfterFocus()
        }
    }

    private var buttonTitle: String {
        switch viewModel.timerState {
        case .running: "일시정지"
        case .paused: "재개"
        case .idle: viewModel.currentState == .idle ? "시작" : "\(viewModel.currentState.description) 시작"
        case .awaitingChoice: "휴식 시작"
        }
    }

}

/// "보상: 커피" 처럼 적어 둔 글을 한두 줄로 보여 줍니다.
struct NoteLine: View {
    let label: String
    let text: String

    var body: some View {
        Text("\(label): \(text)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 긴 휴식까지 남은 집중 사이클을 점으로 표시합니다.
struct CycleDotsView: View {
    let completed: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<max(1, total), id: \.self) { index in
                Circle()
                    .fill(index < completed ? PomodoroState.focus.color : Color.primary.opacity(0.15))
                    .frame(width: 8, height: 8)
            }
        }
        .help("긴 휴식까지의 집중 사이클")
    }
}
