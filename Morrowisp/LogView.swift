// File: LogView.swift
// Description: 집중 기록을 목록과 차트로 보여주는 최상위 뷰입니다.

import SwiftUI
import SwiftData

struct LogView: View {
    @Environment(\.locale) private var locale
    var notesContext: ModelContext? = DataController.shared.transitionContainer?.mainContext
    @ObservedObject var settings = AppSettings.shared
    @State var selectedPeriod: TimePeriod = .weekly
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
                Picker("Choose period", selection: periodBinding) {
                    ForEach(TimePeriod.allCases) { period in
                        Text(period.localizedTitle(locale: locale)).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding()

                if selectedPeriod != .all {
                    PeriodNavigationBar(period: selectedPeriod, offset: $periodOffset)
                    FilteredLogListView(period: selectedPeriod, offset: periodOffset, settings: settings, notesContext: notesContext)
                } else {
                    AllRecordsSummaryView()
                }
            }
            .navigationTitle("Focus history")
            .navigationSplitViewColumnWidth(min: 360, ideal: 380, max: 500)
            .toolbar {
                ToolbarItem {
                    Button(role: .destructive) {
                        showingDeleteAlert = true
                    } label: {
                        Label("Delete all records", systemImage: "trash")
                    }
                }
            }
            .alert("Delete all records?", isPresented: $showingDeleteAlert) {
                Button("Delete", role: .destructive) { deleteAllLogs() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This cannot be undone.")
            }
        } detail: {
            VStack(spacing: 0) {
                if settings.transitionManagementEnabled {
                    WeeklyReviewView(missions: settings.dailyMissions,
                                     completions: settings.focusCompletions, review: settings.weeklyReview)
                    Divider()
                }
                LogChartView(period: selectedPeriod, offset: periodOffset)
            }
            .frame(minWidth: 600)
        }
        .frame(minWidth: 980, minHeight: 640)
    }

    private func deleteAllLogs() {
        try? modelContext.delete(model: FocusLogEntry.self)
        settings.focusCompletions.remove(nil)
        // 기록에 딸린 할 일·보상·다음 시작점 메모도 함께 지웁니다.
        TransitionNote.delete(forSessions: nil, in: notesContext)
    }
}

// MARK: - Period Navigation Bar

struct PeriodNavigationBar: View {
    @Environment(\.locale) private var locale
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

            Text(period.dateRangeLabel(offset: offset, locale: locale))
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)

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
    @Environment(\.locale) private var locale
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

    private var activeDayCount: Int {
        let focusLogs = logs.filter { $0.sessionType == .focus }
        let uniqueDays = Set(focusLogs.map { Calendar.current.startOfDay(for: $0.startTime) })
        return uniqueDays.count
    }

    private var dailyAverageFocusTime: TimeInterval {
        guard activeDayCount > 0 else { return 0 }
        return totalFocusTime / Double(activeDayCount)
    }

    private var dailyAverageSessions: Double {
        guard activeDayCount > 0 else { return 0 }
        return Double(totalFocusSessions) / Double(activeDayCount)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Spacer(minLength: 20)
                StatCard(
                    title: String(localized: "Total focus sessions", bundle: AppLocalization.bundle(for: locale), locale: locale),
                    value: String(localized: "Sessions: \(totalFocusSessions.formatted())", bundle: AppLocalization.bundle(for: locale), locale: locale),
                    systemImage: "timer",
                    color: .blue
                )
                StatCard(
                    title: String(localized: "Total focus time", bundle: AppLocalization.bundle(for: locale), locale: locale),
                    value: formatTime(totalFocusTime),
                    systemImage: "brain.head.profile",
                    color: .blue
                )
                StatCard(
                    title: String(localized: "Total break time", bundle: AppLocalization.bundle(for: locale), locale: locale),
                    value: formatTime(totalBreakTime),
                    systemImage: "cup.and.saucer",
                    color: .green
                )
                StatCard(
                    title: String(localized: "Average daily focus time", bundle: AppLocalization.bundle(for: locale), locale: locale),
                    value: activeDayCount > 0 ? formatTime(dailyAverageFocusTime) : "-",
                    systemImage: "clock.arrow.circlepath",
                    color: .orange
                )
                StatCard(
                    title: String(localized: "Average daily focus sessions", bundle: AppLocalization.bundle(for: locale), locale: locale),
                    value: activeDayCount > 0 ? String(localized: "Sessions: \(dailyAverageSessions.formatted(.number.precision(.fractionLength(1))))", bundle: AppLocalization.bundle(for: locale), locale: locale) : "-",
                    systemImage: "calendar.badge.clock",
                    color: .orange
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
            return String(localized: "\(hours.formatted()) hr \(minutes.formatted()) min", bundle: AppLocalization.bundle(for: locale), locale: locale)
        } else {
            return String(localized: "\(minutes.formatted()) min", bundle: AppLocalization.bundle(for: locale), locale: locale)
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
    @ObservedObject var settings = AppSettings.shared
    /// 세션마다 적어 둔 할 일·보상·다음 시작점 (다른 저장소에 있어 따로 읽습니다)
    @State private var notes: [UUID: TransitionDetails] = [:]

    /// 줄에 보여 줄 글. "전환 관리"를 꺼 두면 보여 주지 않습니다(적어 둔 글은 그대로 있고, 다시 켜면 보입니다).
    static func visibleDetails(for sessionID: UUID, in notes: [UUID: TransitionDetails], transitionManagementEnabled: Bool) -> TransitionDetails? {
        transitionManagementEnabled ? notes[sessionID] : nil
    }

    /// 글을 읽어 올 세션들: 집중 기록만 (휴식에는 적는 글이 없습니다). 꺼 두었으면 읽지 않습니다.
    static func sessionsToLookUp(_ logs: [(id: UUID, type: PomodoroState)], transitionManagementEnabled: Bool) -> [UUID] {
        transitionManagementEnabled ? logs.filter { $0.type == .focus }.map(\.id) : []
    }

    private let notesContext: ModelContext?

    @MainActor
    init(period: TimePeriod, offset: Int, settings: AppSettings = .shared,
         notesContext: ModelContext?? = nil) {
        self.settings = settings
        // 기본값은 앱의 글 저장소. 시험은 다른 컨텍스트(또는 nil)를 넘긴다
        self.notesContext = notesContext ?? DataController.shared.transitionContainer?.mainContext
        _logs = Query(filter: period.predicate(offset: offset), sort: \.startTime, order: .reverse)
    }

    private var groupedLogs: [Date: [FocusLogEntry]] {
        Dictionary(grouping: logs) { log in
            DateHelper.startOfDay(for: log.startTime)
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
                        LogEntryRow(log: log, details: Self.visibleDetails(
                            for: log.id, in: notes, transitionManagementEnabled: settings.transitionManagementEnabled))
                    }
                    .onDelete { indexSet in
                        guard let dayLogs = groupedLogs[day] else { return }
                        let deleted = indexSet.map { dayLogs[$0] }
                        settings.focusCompletions.remove(deleted.map(\.id))
                        TransitionNote.delete(forSessions: deleted.map(\.id), in: notesContext)
                        for log in deleted {
                            modelContext.delete(log)
                        }
                    }
                } header: {
                    LogSectionHeader(day: day, logs: groupedLogs[day] ?? [])
                }
            }
        }
        .listStyle(.inset)
        // 보이는 기록이 바뀔 때마다(새 세션, 기간 이동, 삭제), 그리고 전환 관리를 켜고 끌 때 딸린 글을 다시 읽습니다.
        .task(id: Self.sessionsToLookUp(logs.map { (id: $0.id, type: $0.sessionType) }, transitionManagementEnabled: settings.transitionManagementEnabled)) {
            let ids = Self.sessionsToLookUp(logs.map { (id: $0.id, type: $0.sessionType) }, transitionManagementEnabled: settings.transitionManagementEnabled)
            notes = TransitionNote.details(forSessions: ids, in: notesContext)
        }
    }
}

// MARK: - Log Entry Row

struct LogEntryRow: View {
    @Environment(\.locale) private var locale
    let log: FocusLogEntry
    /// 이 세션에 적어 둔 할 일·보상·다음 시작점 (없으면 nil)
    var details: TransitionDetails? = nil

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        formatter.locale = locale
        return formatter
    }

    private var durationText: String {
        let minutes = Int(log.duration / 60)
        let seconds = Int(log.duration) % 60
        var text = String(localized: "\(minutes.formatted()) min", bundle: AppLocalization.bundle(for: locale), locale: locale)
        if seconds > 0 {
            text += String(localized: " \(seconds.formatted()) sec", bundle: AppLocalization.bundle(for: locale), locale: locale)
        }
        return text
    }

    private var pausedText: String? {
        guard log.pausedDuration >= 1 else { return nil }
        let minutes = Int(log.pausedDuration / 60)
        let seconds = Int(log.pausedDuration) % 60
        if minutes > 0 {
            return String(localized: "Paused for \(minutes.formatted()) min", bundle: AppLocalization.bundle(for: locale), locale: locale)
        } else {
            return String(localized: "Paused for \(seconds.formatted()) sec", bundle: AppLocalization.bundle(for: locale), locale: locale)
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
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(log.sessionType.localizedDescription(locale: locale)).fontWeight(.bold)
                        // 종료 시각은 활동 시간뿐 아니라 일시정지된 시간도 포함해야 합니다.
                        Text(verbatim: "\(timeFormatter.string(from: log.startTime)) - \(timeFormatter.string(from: log.startTime.addingTimeInterval(log.duration + log.pausedDuration)))")
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(durationText)
                            .font(.system(.body, design: .monospaced)).foregroundStyle(.primary)
                        if let paused = pausedText {
                            Text(paused)
                                .font(.caption2).foregroundStyle(.orange)
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
                ForEach(details?.labeledLines(locale: locale) ?? [], id: \.label) { line in
                    // 긴 글은 두 줄까지 접어 보여 줍니다.
                    NoteLine(label: line.label, text: line.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.leading, -8)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }
}

// MARK: - Log Section Header

struct LogSectionHeader: View {
    @Environment(\.locale) private var locale
    let day: Date
    let logs: [FocusLogEntry]

    private var totalFocusTime: TimeInterval {
        logs.filter { $0.sessionType == .focus }.reduce(0) { $0 + $1.duration }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(day.formatted(.dateTime.locale(locale).year().month().day().weekday(.wide)))
                .lineLimit(1)
            Text("Total focus: \(Int(totalFocusTime / 60).formatted()) min")
                .font(.subheadline)
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
    var title: String { localizedTitle() }

    func localizedTitle(locale: Locale = .current) -> String {
        switch self {
        case .weekly: String(localized: "This week", bundle: AppLocalization.bundle(for: locale), locale: locale)
        case .monthly: String(localized: "This month", bundle: AppLocalization.bundle(for: locale), locale: locale)
        case .all: String(localized: "All records", bundle: AppLocalization.bundle(for: locale), locale: locale)
        }
    }

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

    func dateRangeLabel(offset: Int, locale: Locale = .current) -> String {
        let calendar = Calendar.current
        let now = Date()
        let formatter = DateFormatter()
        formatter.locale = locale

        switch self {
        case .weekly:
            guard let startOfThisWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)),
                  let startDate = calendar.date(byAdding: .weekOfYear, value: offset, to: startOfThisWeek),
                  let endDate = calendar.date(byAdding: .day, value: 6, to: startDate)
            else { return "" }
            formatter.setLocalizedDateFormatFromTemplate("Md")
            return "\(formatter.string(from: startDate)) - \(formatter.string(from: endDate))"
        case .monthly:
            guard let startOfThisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
                  let startDate = calendar.date(byAdding: .month, value: offset, to: startOfThisMonth)
            else { return "" }
            formatter.setLocalizedDateFormatFromTemplate("yyyyMMMM")
            return formatter.string(from: startDate)
        case .all:
            return String(localized: "All records", bundle: AppLocalization.bundle(for: locale), locale: locale)
        }
    }
}
