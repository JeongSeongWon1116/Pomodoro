// File: LogView.swift
// Description: 집중 기록을 목록과 차트로 보여주는 최상위 뷰입니다.

import SwiftUI
import SwiftData

struct LogView: View {
    @State private var selectedPeriod: TimePeriod = .weekly
    @State private var periodOffset: Int = 0
    @State private var showingDeleteAlert = false
    @Environment(\.modelContext) private var modelContext

    private var periodBinding: Binding<TimePeriod> {
        Binding(
            get: { selectedPeriod },
            set: { newValue in
                selectedPeriod = newValue
                periodOffset = 0
            }
        )
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                Picker("기간 선택", selection: periodBinding) {
                    ForEach(TimePeriod.allCases) { period in
                        Text(period.rawValue).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                if selectedPeriod != .all {
                    PeriodNavigationBar(period: selectedPeriod, offset: $periodOffset)
                    FilteredLogListView(period: selectedPeriod, offset: periodOffset)
                } else {
                    AllRecordsSummaryView()
                }
            }
            .navigationTitle("집중 기록")
            .frame(minWidth: 320)
            .toolbar {
                ToolbarItem {
                    Button(role: .destructive) {
                        showingDeleteAlert = true
                    } label: {
                        Label("모든 로그 삭제", systemImage: "trash")
                    }
                }
            }
            .alert("모든 로그를 삭제하시겠습니까?", isPresented: $showingDeleteAlert) {
                Button("삭제", role: .destructive) { deleteAllLogs() }
                Button("취소", role: .cancel) {}
            } message: {
                Text("이 동작은 되돌릴 수 없습니다.")
            }
        } detail: {
            LogChartView(period: selectedPeriod, offset: periodOffset)
        }
    }

    private func deleteAllLogs() {
        try? modelContext.delete(model: FocusLogEntry.self)
    }
}

// MARK: - Period Navigation Bar

struct PeriodNavigationBar: View {
    let period: TimePeriod
    @Binding var offset: Int

    var body: some View {
        HStack {
            Button {
                offset -= 1
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.plain)

            Spacer()

            Text(period.dateRangeLabel(offset: offset))
                .font(.subheadline)
                .fontWeight(.medium)

            Spacer()

            Button {
                offset += 1
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.plain)
            .disabled(offset >= 0)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

// MARK: - All Records Summary (전체 기록 탭 사이드바)

struct AllRecordsSummaryView: View {
    @Query private var logs: [FocusLogEntry]

    private var totalFocusSessions: Int {
        logs.filter { $0.sessionType == .focus }.count
    }

    private var totalFocusTime: TimeInterval {
        logs.filter { $0.sessionType == .focus }.reduce(0) { $0 + $1.duration }
    }

    private var totalBreakTime: TimeInterval {
        logs.filter { $0.sessionType == .shortBreak || $0.sessionType == .longBreak }
            .reduce(0) { $0 + $1.duration }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Spacer(minLength: 20)
                StatCard(
                    title: "총 집중 세션",
                    value: "\(totalFocusSessions)회",
                    systemImage: "timer",
                    color: .blue
                )
                StatCard(
                    title: "총 집중 시간",
                    value: formatTime(totalFocusTime),
                    systemImage: "brain.head.profile",
                    color: .blue
                )
                StatCard(
                    title: "총 휴식 시간",
                    value: formatTime(totalBreakTime),
                    systemImage: "cup.and.saucer",
                    color: .green
                )
                Spacer(minLength: 20)
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 {
            return "\(hours)시간 \(minutes)분"
        } else {
            return "\(minutes)분"
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
            }
            Spacer()
        }
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Filtered Log List View

struct FilteredLogListView: View {
    @Query private var logs: [FocusLogEntry]
    @Environment(\.modelContext) private var modelContext

    init(period: TimePeriod, offset: Int) {
        _logs = Query(filter: period.predicate(offset: offset), sort: \.startTime, order: .reverse)
    }

    private var groupedLogs: [Date: [FocusLogEntry]] {
        Dictionary(grouping: logs) { log in
            DateHelper.startOfDayUTC(for: log.startTime)
        }
    }

    private var sortedDays: [Date] {
        groupedLogs.keys.sorted(by: >)
    }

    var body: some View {
        List {
            ForEach(sortedDays, id: \.self) { day in
                Section {
                    ForEach(groupedLogs[day] ?? []) { log in
                        LogEntryRow(log: log)
                    }
                    .onDelete { indexSet in
                        guard let dayLogs = groupedLogs[day] else { return }
                        for index in indexSet {
                            modelContext.delete(dayLogs[index])
                        }
                    }
                } header: {
                    LogSectionHeader(day: day, logs: groupedLogs[day] ?? [])
                }
            }
        }
        .listStyle(.inset)
    }
}

// MARK: - Log Entry Row

struct LogEntryRow: View {
    let log: FocusLogEntry

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private var durationText: String {
        let minutes = Int(log.duration / 60)
        let seconds = Int(log.duration) % 60
        var text = "\(minutes)분"
        if seconds > 0 {
            text += " \(seconds)초"
        }
        return text
    }

    private var pausedText: String? {
        guard log.pausedDuration >= 1 else { return nil }
        let minutes = Int(log.pausedDuration / 60)
        let seconds = Int(log.pausedDuration) % 60
        if minutes > 0 {
            return "\(minutes)분 정지"
        } else {
            return "\(seconds)초 정지"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(log.sessionType.color)
                .frame(width: 4)
                .clipShape(Capsule())
            Image(systemName: log.sessionType.symbolName)
                .font(.title3)
                .foregroundStyle(log.sessionType.color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(log.sessionType.rawValue).fontWeight(.bold)
                Text("\(LogEntryRow.timeFormatter.string(from: log.startTime)) - \(LogEntryRow.timeFormatter.string(from: log.startTime.addingTimeInterval(log.duration)))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(durationText)
                    .font(.system(.body, design: .monospaced)).foregroundStyle(.primary)
                if let paused = pausedText {
                    Text(paused)
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
        }
        .padding(.leading, -8)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }
}

// MARK: - Log Section Header

struct LogSectionHeader: View {
    let day: Date
    let logs: [FocusLogEntry]

    private var totalFocusTime: TimeInterval {
        logs.filter { $0.sessionType == .focus }.reduce(0) { $0 + $1.duration }
    }

    var body: some View {
        HStack {
            Text(day.formatted(.dateTime.year().month().day().weekday(.wide)))
            Spacer()
            Text("총 집중: \(Int(totalFocusTime / 60))분")
                .foregroundStyle(.secondary)
        }
        .font(.headline)
        .padding(.vertical, 8)
        .textCase(nil)
    }
}

// MARK: - TimePeriod Enum

enum TimePeriod: String, CaseIterable, Identifiable {
    case weekly = "이번 주", monthly = "이번 달", all = "전체 기록"
    var id: Self { self }

    func predicate(offset: Int = 0) -> Predicate<FocusLogEntry>? {
        let calendar = Calendar.current
        let now = Date()

        switch self {
        case .weekly:
            guard let startOfThisWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)),
                  let startDate = calendar.date(byAdding: .weekOfYear, value: offset, to: startOfThisWeek),
                  let endDate = calendar.date(byAdding: .weekOfYear, value: 1, to: startDate)
            else { return nil }
            return #Predicate<FocusLogEntry> { $0.startTime >= startDate && $0.startTime < endDate }
        case .monthly:
            guard let startOfThisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
                  let startDate = calendar.date(byAdding: .month, value: offset, to: startOfThisMonth),
                  let endDate = calendar.date(byAdding: .month, value: 1, to: startDate)
            else { return nil }
            return #Predicate<FocusLogEntry> { $0.startTime >= startDate && $0.startTime < endDate }
        case .all:
            return nil
        }
    }

    func dateRangeLabel(offset: Int) -> String {
        let calendar = Calendar.current
        let now = Date()
        let formatter = DateFormatter()

        switch self {
        case .weekly:
            guard let startOfThisWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)),
                  let startDate = calendar.date(byAdding: .weekOfYear, value: offset, to: startOfThisWeek),
                  let endDate = calendar.date(byAdding: .day, value: 6, to: startDate)
            else { return "" }
            formatter.dateFormat = "M.d"
            return "\(formatter.string(from: startDate)) - \(formatter.string(from: endDate))"
        case .monthly:
            guard let startOfThisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
                  let startDate = calendar.date(byAdding: .month, value: offset, to: startOfThisMonth)
            else { return "" }
            formatter.dateFormat = "yyyy년 M월"
            return formatter.string(from: startDate)
        case .all:
            return "전체 기록"
        }
    }
}
