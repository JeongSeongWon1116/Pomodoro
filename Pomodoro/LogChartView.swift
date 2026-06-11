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
    let offset: Int
    @Query private var logs: [FocusLogEntry]

    init(period: TimePeriod, offset: Int = 0) {
        self.period = period
        self.offset = offset
        _logs = Query(filter: period.predicate(offset: offset), sort: \.startTime, order: .forward)
    }

    // 주/월 뷰: 일별 집계
    private var dailyChartData: [AggregatedLogData] {
        let groupedLogs = Dictionary(grouping: logs) { log in
            DateHelper.startOfDay(for: log.startTime)
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

    // 전체 기록 뷰: 월별 집계
    private var monthlyChartData: [AggregatedLogData] {
        let calendar = Calendar.current
        let groupedLogs = Dictionary(grouping: logs) { log -> Date in
            let comps = calendar.dateComponents([.year, .month], from: log.startTime)
            return calendar.date(from: comps) ?? log.startTime
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

    private var chartData: [AggregatedLogData] {
        period == .all ? monthlyChartData : dailyChartData
    }

    private var totalFocusTimeForPeriod: TimeInterval {
        logs.filter { $0.sessionType == .focus }.reduce(0) { $0 + $1.duration }
    }

    private var chartTitle: String {
        switch period {
        case .all: return "전체 집중 기록 (월별)"
        default: return "\(period.dateRangeLabel(offset: offset)) 집중 시간 분석"
        }
    }

    var body: some View {
        VStack {
            Text(chartTitle)
                .font(.title2)
                .padding()

            Text("총 집중 시간: \(formatTimeInterval(totalFocusTimeForPeriod))")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.bottom)

            if chartData.isEmpty {
                ContentUnavailableView("선택된 기간에 기록이 없습니다", systemImage: "chart.bar.xaxis")
            } else {
                let xUnit: Calendar.Component = period == .all ? .month : .day
                let xCount = period == .monthly ? 7 : 1

                Chart(chartData) { data in
                    BarMark(
                        x: .value("Date", data.date, unit: xUnit),
                        y: .value("Minutes", data.focusDuration / 60)
                    ).foregroundStyle(by: .value("Type", PomodoroState.focus.rawValue))

                    BarMark(
                        x: .value("Date", data.date, unit: xUnit),
                        y: .value("Minutes", data.shortBreakDuration / 60)
                    ).foregroundStyle(by: .value("Type", PomodoroState.shortBreak.rawValue))

                    BarMark(
                        x: .value("Date", data.date, unit: xUnit),
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
                    AxisMarks(values: .stride(by: xUnit, count: xCount)) { value in
                        AxisGridLine()
                        AxisTick()
                        if value.as(Date.self) != nil {
                            if period == .all {
                                AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits))
                            } else {
                                AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
                            }
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
