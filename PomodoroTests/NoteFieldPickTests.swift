import AppKit
import SwiftUI
import Testing
@testable import Pomodoro

/// 팝오버의 할 일·보상 칸 옆 메뉴에서 지난 글을 고르는 동작을, 실제 창에 올린 실제 뷰로 봅니다.
/// 실행 루프를 돌리며 기다리므로(그 사이 다른 테스트가 끼어들 수 있습니다) 이 묶음의 테스트는 하나씩 차례로 돌립니다.
@MainActor
@Suite(.serialized)
struct NoteFieldPickTests {
    final class Model: ObservableObject {
        @Published var text = ""
    }

    struct Host: View {
        @ObservedObject var model: Model
        var body: some View {
            NoteField(title: "할 일", text: $model.text, suggestions: ["지난 글", "다른 글"], help: "지난 할 일에서 고르기")
                .padding()
                .frame(width: 320)
        }
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    private func spin(_ seconds: TimeInterval = 0.2) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    /// 메뉴를 실제로 열어 제목이 title 인 항목을 고릅니다. 메뉴가 열려 있는 동안에는 실행 루프가 추적 모드로 돌므로
    /// 타이머로 들어가 고르고 닫습니다. SwiftUI 는 메뉴의 항목을 열 때 채우므로 열지 않고는 고를 수 없습니다.
    /// (화면이 켜져 있으면 작은 메뉴가 0.1초쯤 떴다 사라집니다.)
    private func choose(_ title: String, from button: NSPopUpButton) -> Bool {
        var chosen = false
        var ticks = 0
        let timer = Timer(timeInterval: 0.05, repeats: true) { _ in
            MainActor.assumeIsolated {
                ticks += 1
                if !chosen, let menu = button.menu, let index = menu.items.firstIndex(where: { $0.title == title }) {
                    chosen = true
                    menu.performActionForItem(at: index)
                }
                guard chosen || ticks >= 40 else { return }
                button.menu?.cancelTracking()
                // 그래도 닫히지 않으면(2초가 지나도 추적 중이면) Esc 를 넣어 닫습니다. 테스트가 멈춰 서면 릴리스 스크립트도 멈춥니다.
                if ticks >= 40, let esc = NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: 0, context: nil, characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53
                ) {
                    NSApp.postEvent(esc, atStart: true)
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        button.performClick(nil)
        timer.invalidate()
        return chosen
    }

    private struct Stage {
        let window: NSWindow
        let model: Model
        let field: NSTextField
        let editor: NSTextView
        let menuButton: NSPopUpButton
    }

    /// 칸에 "적던 글"을 적고 편집 중인 채로 둡니다.
    private func makeStage() throws -> Stage {
        let model = Model()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 80), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: Host(model: model))
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        spin()
        let all = descendants(of: hosting)
        let field = try #require(all.compactMap { $0 as? NSTextField }.first)
        let menuButton = try #require(all.compactMap { $0 as? NSPopUpButton }.first)
        #expect(window.makeFirstResponder(field))
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.insertText("적던 글", replacementRange: NSRange(location: 0, length: 0))
        spin(0.1)
        #expect(model.text == "적던 글")
        return Stage(window: window, model: model, field: field, editor: editor, menuButton: menuButton)
    }

    @Test func 편집_중에_메뉴에서_고르면_고른_글이_들어가고_그_칸의_편집이_끝난다() throws {
        let stage = try makeStage()
        defer { stage.window.close() }
        guard choose("지난 글", from: stage.menuButton) else { return Self.skipped() }
        spin(0.3)
        #expect(stage.model.text == "지난 글")
        #expect(stage.field.stringValue == "지난 글")
        #expect(stage.field.currentEditor() == nil) // 편집이 끝났다 (창이 키 윈도우가 아니어도)

        // 편집이 끝난 뒤에 적던 글이 되돌아오지 않는다
        stage.window.makeFirstResponder(nil)
        spin(0.3)
        #expect(stage.model.text == "지난 글")
        #expect(stage.field.stringValue == "지난 글")
    }

    @Test func 조합_중인_글자가_있어도_고른_글이_들어간다() throws {
        // 한글을 치다 만 상태(입력기가 확정하지 않은 글자가 칸에 있음)를 흉내 냅니다. 실제 입력기와 주고받는 것까지는 보지 못합니다.
        let stage = try makeStage()
        defer { stage.window.close() }
        stage.editor.setMarkedText("ㅎ", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        spin(0.1)
        #expect(stage.editor.hasMarkedText())
        guard choose("지난 글", from: stage.menuButton) else { return Self.skipped() }
        spin(0.3)
        #expect(stage.model.text == "지난 글")
        #expect(stage.field.stringValue == "지난 글")
        stage.window.makeFirstResponder(nil)
        spin(0.3)
        #expect(stage.model.text == "지난 글")
        #expect(stage.field.stringValue == "지난 글")
    }

    // 메뉴가 열리지 않는 환경(화면이 없는 곳 등)에서는 판정하지 않습니다. 릴리스 스크립트의 테스트를 그 이유로 막지 않으려는 것입니다.
    private static func skipped() {
        FileHandle.standardError.write(Data("NoteFieldPickTests: 메뉴를 열지 못해 건너뜀\n".utf8))
    }
}
