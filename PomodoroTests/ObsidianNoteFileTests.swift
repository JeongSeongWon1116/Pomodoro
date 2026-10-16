//
//  ObsidianNoteFileTests.swift
//  PomodoroTests
//
//  데일리 노트 파일 읽기/쓰기와 섹션 경계 판정을 임시 폴더에서 검증합니다.
//  (실제 Obsidian 보관함은 건드리지 않습니다.)
//

import Foundation
import Testing
@testable import Pomodoro

@MainActor
struct ObsidianNoteFileTests {

    private let heading = ObsidianExporter.sectionHeading
    private let stats = ObsidianExporter.statsPrefix
    private let line = "- 🍅 집중 25분 (09:00–09:25)"

    /// 테스트마다 따로 쓰는 임시 폴더를 만들고, 끝나면 지웁니다.
    private func withTempFolder(_ body: (URL) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("PomodoroTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try body(folder)
    }

    // MARK: - 파일 읽기/쓰기

    @Test func 빈_미션과_기록으로는_기존_노트를_바꾸지_않는다() {
        for content in ["", "# 오늘\n메모", "# 오늘\n메모\n"] {
            #expect(ObsidianExporter.insert(line: nil, into: content, mission: DailyMission()) == content)
            #expect(ObsidianExporter.insert(line: "", into: content) == content)
        }
    }

    @Test func 빈_미션과_기록으로는_파일을_만들지_않는다() throws {
        try withTempFolder { folder in
            let note = folder.appendingPathComponent("empty.md")
            try ObsidianExporter.appendLine(nil, toNoteAt: note, mission: DailyMission())
            #expect(!FileManager.default.fileExists(atPath: note.path))
        }
    }

    @Test func 기록이_없는_미션_섹션에_빈_줄을_중복하지_않는다() {
        let mission = DailyMission(text: "초안")
        let section = "\(heading)\n\(ObsidianExporter.missionPrefix)초안\n\(stats) 🍅 0회 · 총 0초\n"
        #expect(ObsidianExporter.insert(line: nil, into: "", mission: mission) == section)
        let content = section + "\n## 메모\n남길 내용\n"
        #expect(ObsidianExporter.insert(line: nil, into: content, mission: mission) == content)
    }

    @Test func 내용이_같으면_파일_수정_시각도_그대로다() throws {
        try withTempFolder { folder in
            let note = folder.appendingPathComponent("unchanged.md")
            let original = "\(heading)\n\(stats) 🍅 1회 · 총 25분\n\(line)\n"
            try original.write(to: note, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000_000)], ofItemAtPath: note.path)
            let before = try FileManager.default.attributesOfItem(atPath: note.path)[.modificationDate] as? Date
            try ObsidianExporter.appendLine(nil, toNoteAt: note)
            let after = try FileManager.default.attributesOfItem(atPath: note.path)[.modificationDate] as? Date
            #expect(before != nil)
            #expect(after == before)
            #expect(try String(contentsOf: note, encoding: .utf8) == original)
        }
    }

    @Test func 세션_추가에서_빈_로컬_미션은_노트의_미션을_보존한다() throws {
        try withTempFolder { folder in
            let note = folder.appendingPathComponent("session.md")
            let missionLine = ObsidianExporter.missionPrefix + "다른 기기의 미션"
            let original = "\(heading)\n\(missionLine)\n\(stats) 🍅 0회 · 총 0초\n"
            let start = Date(timeIntervalSince1970: 1_000_000)
            let entry = FocusLogEntry(startTime: start, endTime: start.addingTimeInterval(1500),
                                      duration: 1500, sessionType: .focus)
            for mission in [DailyMission(), DailyMission(text: " \n\t ")] {
                try original.write(to: note, atomically: true, encoding: .utf8)
                try ObsidianExporter.appendSession(entry, toNoteAt: note, mission: mission)
                let written = try String(contentsOf: note, encoding: .utf8)
                #expect(written.contains(missionLine + "\n"))
                #expect(written.contains(ObsidianExporter.markdownLine(for: entry)))
                #expect(written.contains("🍅 1회 · 총 25분"))
            }
        }
    }

    @Test func 노트가_없으면_새로_만든다() throws {
        try withTempFolder { folder in
            let note = folder.appendingPathComponent("2026-10-04.md")
            try ObsidianExporter.appendLine(line, toNoteAt: note)
            let written = try String(contentsOf: note, encoding: .utf8)
            #expect(written == "\(heading)\n\(stats) 🍅 1회 · 총 25분\n\(line)\n")
        }
    }

    @Test func 읽을_수_있는_노트는_기존_내용을_보존하고_추가한다() throws {
        try withTempFolder { folder in
            let note = folder.appendingPathComponent("2026-10-04.md")
            try "# 데일리 노트\n오늘의 메모\n".write(to: note, atomically: true, encoding: .utf8)
            try ObsidianExporter.appendLine(line, toNoteAt: note)
            let written = try String(contentsOf: note, encoding: .utf8)
            #expect(written == "# 데일리 노트\n오늘의 메모\n\n\(heading)\n\(stats) 🍅 1회 · 총 25분\n\(line)\n")
        }
    }

    @Test func UTF8로_읽을_수_없는_기존_노트는_덮어쓰지_않고_오류를_낸다() throws {
        try withTempFolder { folder in
            let note = folder.appendingPathComponent("2026-10-04.md")
            // UTF-8 로 해석할 수 없는 바이트열 (다른 인코딩으로 저장된 노트를 흉내 냅니다)
            let original = Data([0xFF, 0xFE, 0xB5, 0xA5, 0xC0, 0xCF, 0xB8, 0xAE, 0x0A])
            try original.write(to: note)

            #expect(throws: (any Error).self) {
                try ObsidianExporter.appendLine(line, toNoteAt: note)
            }
            #expect(try Data(contentsOf: note) == original) // 원본이 그대로 남아야 합니다
        }
    }

    @Test func iCloud에서_아직_내려받지_않은_노트는_새로_만들지_않고_오류를_낸다() throws {
        try withTempFolder { folder in
            let note = folder.appendingPathComponent("2026-10-04.md")
            // 내려받지 않은 iCloud 파일은 ".이름.icloud" 자리표시자로만 존재합니다.
            let placeholder = folder.appendingPathComponent(".2026-10-04.md.icloud")
            try Data([0x62, 0x70, 0x6C, 0x69, 0x73, 0x74]).write(to: placeholder)

            #expect(throws: (any Error).self) {
                try ObsidianExporter.appendLine(line, toNoteAt: note)
            }
            #expect(!FileManager.default.fileExists(atPath: note.path))
        }
    }

    // MARK: - 섹션 경계

    @Test func 본문_중간에_헤딩_문구가_들어_있어도_섹션으로_보지_않는다() {
        let content = "메모: 내일부터 \(heading) 기록을 써 보자\n다음 줄\n"
        let result = ObsidianExporter.insert(line: line, into: content)
        #expect(result == content + "\n\(heading)\n\(stats) 🍅 1회 · 총 25분\n\(line)\n")
    }

    @Test func 해시태그_줄은_섹션의_끝이_아니다() {
        let content = "\(heading)\n\(stats) 🍅 1회 · 총 25분\n\(line)\n#회고 #집중\n\n## 할 일\n- 회의 준비\n"
        let second = "- ☕️ 짧은 휴식 5분 (09:25–09:30)"
        let result = ObsidianExporter.insert(line: second, into: content)
        #expect(result == "\(heading)\n\(stats) 🍅 1회 · 총 25분\n\(line)\n#회고 #집중\n\(second)\n\n## 할 일\n- 회의 준비\n")
    }

    @Test func 더_깊은_단계의_헤딩에서도_섹션이_끝난다() {
        let content = "\(heading)\n\(stats) 🍅 1회 · 총 25분\n\(line)\n### 메모\n내용\n"
        let second = "- ☕️ 짧은 휴식 5분 (09:25–09:30)"
        let result = ObsidianExporter.insert(line: second, into: content)
        #expect(result == "\(heading)\n\(stats) 🍅 1회 · 총 25분\n\(line)\n\(second)\n\n### 메모\n내용\n")
    }
}
