// File: LogView.swift
// Description: 집중 기록을 목록과 차트로 보여주는 최상위 뷰입니다.

import SwiftUI
import SwiftData

struct LogView: View {
    @State private var selectedPeriod: TimePeriod = .weekly
    @State private var showingDeleteAlert = false
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                Picker("기간 선택", selection: $selectedPeriod) {
                    ForEach(TimePeriod.allCases) { period in
                        Text(period.rawValue).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                FilteredLogListView(period: selectedPeriod)
            }
            .navigationTitle("집중 기록")
            .frame(minWidth: 400)
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
            LogChartView(period: selectedPeriod)
        }
        .background(BringToFront())
    }
    
    private func deleteAllLogs() {
        try? modelContext.delete(model: FocusLogEntry.self)
    }
}

struct FilteredLogListView: View {
    @Query private var logs: [FocusLogEntry]
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.modelContext) private var modelContext
    init(period: TimePeriod) {
        _logs = Query(filter: period.predicate, sort: \.startTime, order: .reverse)
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
                    .onDelete{ indexSet in guard let dayLogs = groupedLogs[day] else {return}
                        for index in indexSet {
                            let logToDelete = dayLogs[index]
                            modelContext.delete(logToDelete)
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

struct LogEntryRow: View {
    let log: FocusLogEntry
    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }

    var body: some View {
        HStack(spacing: 12) {
            Rectangle().fill(log.sessionType.color).frame(width: 5)
            Text(log.sessionType.emoji).font(.title2)
            VStack(alignment: .leading) {
                Text(log.sessionType.rawValue).fontWeight(.bold)
                Text("\(timeFormatter.string(from: log.startTime)) - \(timeFormatter.string(from: log.startTime.addingTimeInterval(log.duration)))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(Int(log.duration / 60))분 \(Int(log.duration) % 60)초")
                .font(.system(.body, design: .monospaced)).foregroundStyle(.primary)
        }
        .padding(.leading, -8)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }
}

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

enum TimePeriod: String, CaseIterable, Identifiable {
    case weekly = "이번 주", monthly = "이번 달", all = "전체 기록"
    var id: Self { self }

    var predicate: Predicate<FocusLogEntry>? {
        let calendar = Calendar.current
        let now = Date()
        
        switch self {
        case .weekly:
            guard let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) else { return nil }
            return #Predicate<FocusLogEntry> { $0.startTime >= startOfWeek }
        case .monthly:
            guard let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) else { return nil }
            return #Predicate<FocusLogEntry> { $0.startTime >= startOfMonth }
        case .all:
            return nil
        }
    }
}
