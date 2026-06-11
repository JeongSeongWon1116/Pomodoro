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
        let minutes = max(1, Int((entry.duration / 60).rounded()))
        return "- \(entry.sessionType.emoji) \(entry.sessionType.rawValue) \(minutes)분 (\(start)–\(end))"
    }

    /// 뽀모도로 섹션의 끝(다음 헤딩 직전 또는 파일 끝)에 줄을 삽입합니다.
    static func insert(line: String, into content: String) -> String {
        guard let headingRange = content.range(of: sectionHeading) else {
            var result = content
            if !result.isEmpty && !result.hasSuffix("\n") { result += "\n" }
            if !result.isEmpty { result += "\n" }
            return result + sectionHeading + "\n" + line + "\n"
        }

        let afterHeading = headingRange.upperBound
        let insertionIndex = content.range(of: "\n#", range: afterHeading..<content.endIndex)?.lowerBound
            ?? content.endIndex

        var section = String(content[afterHeading..<insertionIndex])
        while section.hasSuffix("\n") { section.removeLast() }

        let remainder = insertionIndex < content.endIndex ? String(content[insertionIndex...]) : ""
        return String(content[..<afterHeading]) + section + "\n" + line + "\n" + remainder
    }
}
