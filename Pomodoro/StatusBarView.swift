// File: StatusBarView.swift
// Description: 메뉴 막대에 표시될 커스텀 UI입니다.

import SwiftUI

struct StatusBarView: View {
    let emoji: String
    let timerState: TimerState
    let progress: Double
    let color: Color
    let timeRemainingString: String

    var body: some View {
        HStack(spacing: 4) {
            Text(emoji)
                .font(.title)
                .frame(width: 22)
            
            // Show EITHER the time remaining OR the progress bar, but keep them both in the layout.
            // This creates a stable layout that is less prone to SwiftUI update bugs in MenuBarExtra.
            ZStack {
                Text(timeRemainingString)
                    .font(.system(.body, design: .monospaced))
                    .opacity(timerState == .idle ? 1 : 0)

                BatteryProgressBar(progress: progress, color: color)
                    .opacity(timerState == .running || timerState == .paused ? 1 : 0)
            }
            .frame(width: 50)
        }
        .padding(.horizontal, 8)
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
        .frame(height: 14)
    }
}
