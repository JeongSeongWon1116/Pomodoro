// File: StatusBarView.swift
// Description: 메뉴 막대에 표시될 커스텀 UI입니다.

import SwiftUI

struct StatusBarView: View {
    let emoji: String
    let timerState: TimerState
    let progress: Double
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Text(emoji)
                .font(.title)
                .frame(width: 22)
            
            if timerState == .running || timerState == .paused {
                BatteryProgressBar(progress: progress, color: color)
                    .frame(width: 35) // 명시적으로 너비 지정
            }
        }
        .padding(.horizontal, 6)
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
        .frame(width: 35, height: 14)
    }
}
