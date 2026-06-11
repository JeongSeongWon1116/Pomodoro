// File: ObsidianExporter.swift
// Description: 완료된 세션을 Obsidian 보관함(Vault)의 데일리 노트(yyyy-MM-dd.md)에
// 마크다운으로 기록하는 연동 모듈입니다. 별도의 Obsidian 플러그인 없이 동작합니다.

import Foundation
import AppKit

@MainActor
final class ObsidianExporter: ObservableObject {
    static let shared = ObsidianExporter()

    private static let enabledKey = "obsidianSyncEnabled"
    private static let bookmarkKey = "obsidianFolderBookmark"
    static let sectionHeading = "## 🍅 뽀모도로"
    static let statsPrefix = "**하루 통계:**"

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey) }
    }
    @Published private(set) var folderName: String?

    private init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        self.folderName = nil
        if let url = resolveFolderURL() {
            self.folderName = url.lastPathComponent
        }
    }

    var isFolderSelected: Bool {
        UserDefaults.standard.data(forKey: Self.bookmarkKey) != nil
    }

    /// 데일리 노트가 저장되는 보관함 폴더를 선택합니다.
    /// 샌드박스 환경에서 재실행 후에도 접근할 수 있도록 보안 범위 북마크로 저장합니다.
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "선택"
        panel.message = "데일리 노트가 저장되는 Obsidian 폴더를 선택하세요"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        saveBookmark(for: url)
    }

    private func saveBookmark(for url: URL) {
        do {
            let data = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
            folderName = url.lastPathComponent
        } catch {
            print("Obsidian 폴더 북마크 저장 실패: \(error)")
        }
    }

    private func resolveFolderURL() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        if isStale {
            saveBookmark(for: url)
        }
        return url
    }

    /// 완료된 세션을 해당 날짜의 데일리 노트에 추가합니다.
    /// 노트가 없으면 새로 만들고, "## 🍅 뽀모도로" 섹션이 있으면 그 끝에 줄을 추가합니다.
    func appendSession(_ entry: FocusLogEntry) {
        guard isEnabled, let folder = resolveFolderURL() else { return }
        guard folder.startAccessingSecurityScopedResource() else {
            print("Obsidian 폴더 접근 권한을 얻지 못했습니다.")
            return
        }
        defer { folder.stopAccessingSecurityScopedResource() }

        let noteURL = folder.appendingPathComponent(Self.noteFileName(for: entry.startTime))
        let line = Self.markdownLine(for: entry)
        do {
            let existing = (try? String(contentsOf: noteURL, encoding: .utf8)) ?? ""
            let updated = Self.insert(line: line, into: existing)
            try updated.write(to: noteURL, atomically: true, encoding: .utf8)
        } catch {
            print("Obsidian 데일리 노트 기록 실패: \(error)")
        }
    }

    static func noteFileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date) + ".md"
    }

    static func markdownLine(for entry: FocusLogEntry) -> String {
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let start = timeFormatter.string(from: entry.startTime)
        // 종료 시각 = 시작 + 활동 시간 + 정지 시간
        let end = timeFormatter.string(from: entry.startTime.addingTimeInterval(entry.duration + entry.pausedDuration))
        return "- \(entry.sessionType.emoji) \(entry.sessionType.rawValue) \(durationText(entry.duration)) (\(start)–\(end))"
    }

    /// 초 단위까지 표시하는 시간 문자열 (예: "1시간 2분 3초", "25분", "42초")
    static func durationText(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        var parts: [String] = []
        if hours > 0 { parts.append("\(hours)시간") }
        if minutes > 0 { parts.append("\(minutes)분") }
        if seconds > 0 || parts.isEmpty { parts.append("\(seconds)초") }
        return parts.joined(separator: " ")
    }

    /// 섹션에 새 기록 줄을 추가하고, 하루 통계 줄을 다시 계산하여 하나로 유지합니다.
    static func insert(line: String, into content: String) -> String {
        let (prefix, body, suffix) = splitSection(in: content)

        // 기존 통계 줄은 버리고(중복 방지) 나머지 줄은 그대로 보존합니다.
        var lines = body
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { !$0.hasPrefix(statsPrefix) }
        lines.append(line)

        let section = sectionHeading + "\n" + statsLine(for: lines) + "\n" + lines.joined(separator: "\n") + "\n"
        return prefix + section + suffix
    }

    /// 섹션 줄들로부터 하루 통계(집중 횟수 + 총 집중 시간)를 계산합니다.
    static func statsLine(for lines: [String]) -> String {
        let focusLines = lines.filter { $0.hasPrefix("- " + PomodoroState.focus.emoji) }
        let totalSeconds = focusLines.reduce(0) { $0 + parseDurationSeconds(fromLine: $1) }
        return "\(statsPrefix) \(PomodoroState.focus.emoji) \(focusLines.count)회 · 총 \(durationText(TimeInterval(totalSeconds)))"
    }

    /// "- 🍅 집중 24분 13초 (09:00–09:25)" 형태의 줄에서 시간을 초로 파싱합니다.
    static func parseDurationSeconds(fromLine line: String) -> Int {
        let beforeTimes = line.components(separatedBy: " (").first ?? line
        var seconds = 0
        for token in beforeTimes.split(separator: " ") {
            if token.hasSuffix("시간"), let value = Int(token.dropLast(2)) {
                seconds += value * 3600
            } else if token.hasSuffix("분"), let value = Int(token.dropLast()) {
                seconds += value * 60
            } else if token.hasSuffix("초"), let value = Int(token.dropLast()) {
                seconds += value
            }
        }
        return seconds
    }

    /// 노트를 (섹션 앞, 섹션 본문, 섹션 뒤)로 분리합니다. 섹션이 없으면 본문은 빈 문자열입니다.
    private static func splitSection(in content: String) -> (prefix: String, body: String, suffix: String) {
        guard let headingRange = content.range(of: sectionHeading) else {
            var prefix = content
            if !prefix.isEmpty && !prefix.hasSuffix("\n") { prefix += "\n" }
            if !prefix.isEmpty { prefix += "\n" }
            return (prefix, "", "")
        }

        let afterHeading = headingRange.upperBound
        let bodyEnd = content.range(of: "\n#", range: afterHeading..<content.endIndex)?.lowerBound
            ?? content.endIndex

        let prefix = String(content[..<headingRange.lowerBound])
        let body = String(content[afterHeading..<bodyEnd])
        let suffix = bodyEnd < content.endIndex ? String(content[bodyEnd...]) : ""
        return (prefix, body, suffix)
    }
}
