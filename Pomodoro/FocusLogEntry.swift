// File: FocusLogEntry.swift
// Description: SwiftData가 관리하는 데이터 모델입니다.

import Foundation
import SwiftData
import SwiftUI

@Model
final class FocusLogEntry {
    var id: UUID
    var startTime: Date
    var endTime: Date
    var duration: TimeInterval // 실제 집중/휴식 시간
    var pausedDuration: TimeInterval // 정지한 시간
    var sessionType: PomodoroState

    init(id: UUID = UUID(), startTime: Date, endTime: Date, duration: TimeInterval, pausedDuration: TimeInterval = 0, sessionType: PomodoroState) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.duration = duration
        self.pausedDuration = pausedDuration
        self.sessionType = sessionType
    }
}

extension PomodoroState {
    var color: Color {
        switch self {
        case .focus: .blue
        case .shortBreak: .green
        case .longBreak: .purple
        case .idle: .gray
        }
    }
}
