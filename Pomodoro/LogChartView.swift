// File: LogChartView.swift
// Description: 로그 데이터를 시각화하는 차트 뷰입니다.

import SwiftUI
import Charts
import SwiftData

struct AggregatedLogData: Identifiable {
    let id: Date
    var date: Date
    var focusDuration: TimeInterval = 0
    var shortBreakDuration: TimeInterval = 0
    var longBreakDuration: TimeInterval = 0
}

struct LogChartView: View {
    let period: TimePeriod
    @Query private var logs: [FocusLogEntry]

    init(period: TimePeriod) {
        self.period = period
        // [수정됨] .ascending을 .forward로 변경하여 SwiftData @Query 문법에 맞게 수정
        _logs = Query(filter: period.predicate, sort: \.startTime, order: .forward)
    }

    private var chartData: [AggregatedLogData] {
        let groupedLogs = Dictionary(grouping: logs) { log in
            DateHelper.startOfDayUTC(for: log.startTime)
        }
        
        var aggregatedData = [Date: AggregatedLogData]()
        for (date, logsInGroup) in groupedLogs {
            var data = AggregatedLogData(id: date, date: date)
            for log in logsInGroup {
                switch log.sessionType {
                case .focus: data.focusDuration += log.duration
                case .shortBreak: data.shortBreakDuration += log.duration
                case .longBreak: data.longBreakDuration += log.duration
                default: break
                }
            }
            aggregatedData[date] = data
        }
        return aggregatedData.values.sorted { $0.date < $1.date }
    }

    private var totalFocusTimeForPeriod: TimeInterval {
        logs.filter { $0.sessionType == .focus }.reduce(0) { $0 + $1.duration }
    }

    var body: some View {
        VStack {
            Text("\(period.rawValue) 집중 시간 분석").font(.title2).padding()
            
            Text("총 집중 시간: \(formatTimeInterval(totalFocusTimeForPeriod))")
                .font(.headline).foregroundStyle(.secondary).padding(.bottom)

            if chartData.isEmpty {
                ContentUnavailableView("선택된 기간에 기록이 없습니다", systemImage: "chart.bar.xaxis")
            } else {
                Chart(chartData) { data in
                    BarMark(
                        x: .value("Date", data.date, unit: .day),
                        y: .value("Minutes", data.focusDuration / 60)
                    ).foregroundStyle(by: .value("Type", PomodoroState.focus.rawValue))
                    
                    BarMark(
                        x: .value("Date", data.date, unit: .day),
                        y: .value("Minutes", data.shortBreakDuration / 60)
                    ).foregroundStyle(by: .value("Type", PomodoroState.shortBreak.rawValue))
                    
                    BarMark(
                        x: .value("Date", data.date, unit: .day),
                        y: .value("Minutes", data.longBreakDuration / 60)
                    ).foregroundStyle(by: .value("Type", PomodoroState.longBreak.rawValue))
                }
                .chartForegroundStyleScale([
                    PomodoroState.focus.rawValue: PomodoroState.focus.color,
                    PomodoroState.shortBreak.rawValue: PomodoroState.shortBreak.color,
                    PomodoroState.longBreak.rawValue: PomodoroState.longBreak.color
                ])
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        if let minutes = value.as(Int.self) {
                            AxisValueLabel("\(minutes)분")
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: period == .monthly ? 7 : 1 )) { value in
                        AxisGridLine()
                        AxisTick()
                        if let date = value.as(Date.self) {
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
                        }
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 400, minHeight: 300)
    }
    
    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 {
            return "\(hours)시간 \(minutes)분"
        } else {
            return "\(minutes)분"
        }
    }
}
