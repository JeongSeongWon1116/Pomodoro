[한국어](OBSIDIAN.ko.md)

# Obsidian integration

Pomodoro can write session records to your daily notes without an Obsidian plugin. An Obsidian vault is a folder of Markdown files, so the app writes directly to the selected folder and Obsidian reflects those changes.

The app UI and exported labels are currently in Korean. Examples below preserve the actual output, including the labels used by the Dataview query.

## Setup

1. Click the Pomodoro menu bar icon to open the popover, then click the gear (settings) button.
2. In the **Obsidian** tab, enable **Write to daily notes when a session ends (세션이 끝나면 데일리 노트에 기록)**.
3. Click **Choose folder (폴더 선택)** and select the folder containing your daily notes.
   - If daily notes live at the vault root, select the vault folder.
   - If you use a subfolder such as `Daily/`, select that folder.
   - The app saves access as a security-scoped bookmark, so the selection persists across restarts.

## How it works

When a focus or break session ends, the app writes to a `yyyy-MM-dd.md` file. Session exports use the session's start date. It creates the file if needed. In an existing file, it appends the record to the `## 🍅 뽀모도로` section, or adds that section at the bottom if it is missing. Other note content is left intact.

```markdown
## 🍅 뽀모도로
**하루 통계:** 🍅 3회 · 총 1시간 1분 30초
- 🍅 집중 25분 (09:00–09:25)
- ☕️ 짧은 휴식 5분 (09:25–09:30)
- 🍅 집중 24분 17초 (09:31–09:58)
- 🍅 집중 12분 13초 (10:10–10:22)
```

- Durations are recorded **down to the second**. Resetting or skipping a session partway through still preserves the actual time spent.
- The end clock time includes pauses; the duration represents actual active time.
- The **daily statistics (하루 통계)** line is recalculated after each session and kept as **a single line**. It counts focus (🍅) records in the section, excluding breaks.

### Task, reward, and next starting point

If you wrote a task, reward, or next starting point, or extended focus, those details appear as tab-indented lines beneath the session. Only supplied details are written; without them, only the session line remains.

```markdown
- 🍅 집중 35분 (09:00–09:35)
	- 할 일: 3장 초안
	- 보상: 커피
	- 다음 시작점: 3.2절 두 번째 문단부터
	- 연장: +10분
```

The example records a chapter draft as the task, coffee as the reward, a paragraph to return to, and a 10-minute extension.

- The session-line format is unchanged, and indented details do not count toward daily statistics.
- Line breaks in your text are flattened to one line. `%%` (Obsidian's comment marker) becomes `% %` so that following content is not hidden.
- Only a next starting point entered on the end-of-focus choice screen is exported.

### Daily mission (1.4)

With integration enabled, writing or editing today's main mission updates one indented line at the top of that day's Pomodoro section. Marking it done also updates the line. Session records and existing daily statistics are preserved. Weekly reflection notes are not exported.

## Use statistics in Obsidian (optional)

Daily statistics are already written into each note. To collect them across days, you can use the [Dataview](https://blacksmithgu.github.io/obsidian-dataview/) plugin:

````markdown
```dataviewjs
const pages = dv.pages('"Daily"').sort(p => p.file.name, 'desc').limit(7);
for (const page of pages) {
    const content = await dv.io.load(page.file.path);
    const match = content.match(/^\*\*하루 통계:\*\* 🍅 (\d+)회 · 총 (.+)$/m);
    if (match) dv.paragraph(`**${page.file.name}**: 🍅 ${match[1]}회, 총 ${match[2]}`);
}
```
````

Replace `"Daily"` with your daily-note folder path. Keep the Korean matching text unchanged: it matches the app's exported labels.

## Comparison with other approaches

| Approach | Advantages | Limitations |
|---|---|---|
| **Direct folder writes (current approach)** | Works while Obsidian is closed; no plugin needed | Requires selecting a folder once |
| Obsidian URI (`obsidian://`) with Advanced URI | Simple setup | Activates Obsidian on each write; requires a plugin; cannot write in the background |
| A dedicated Obsidian community plugin | Could provide UI within Obsidian | Requires a separate project; app-to-plugin data transfer would still use files |

Daily-note filename formats other than `yyyy-MM-dd` (Obsidian's default) are not currently supported.
