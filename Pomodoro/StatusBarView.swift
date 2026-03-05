// File: StatusBarView.swift
// Description: 메뉴 막대에 표시될 커스텀 UI입니다.

import SwiftUI

struct StatusBarView: View {
    @EnvironmentObject var viewModel: PomodoroViewModel

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: viewModel.currentState.symbolName)
                .imageScale(.large)
                .foregroundStyle(.primary)

            if viewModel.timerState == .running || viewModel.timerState == .paused {
                LinearProgressBar(progress: viewModel.progress, color: viewModel.currentState.color)
            }
        }
        .padding(.horizontal, 6)
        .fixedSize()
    }
}

struct LinearProgressBar: View {
    var progress: Double
    var color: Color

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.primary.opacity(0.15))
                .frame(width: 34, height: 6)
            Capsule()
                .fill(color)
                .frame(width: max(0, 34 * CGFloat(progress)), height: 6)
        }
    }
}
