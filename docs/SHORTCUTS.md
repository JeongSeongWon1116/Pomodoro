[한국어](SHORTCUTS.ko.md)

# Morrowisp — Shortcuts integration

Morrowisp can run shortcuts you have created in the macOS **Shortcuts** app when focus begins and ends. Examples include turning Do Not Disturb (a Focus mode) on or off, playing or stopping music, and changing lights.

The app UI supports English and Korean; the labels below include the Korean text as a reference.

## Setup

1. Create two shortcuts in Shortcuts. For Do Not Disturb, for example:
   - **방해금지 켜기** — use the Set Focus action to turn Do Not Disturb on.
   - **방해금지 끄기** — use the Set Focus action to turn Do Not Disturb off.
2. Click the Morrowisp menu bar icon → gear (settings) → **Shortcuts (단축어)**.
3. Enter each shortcut's **exact name** in **When focus starts (집중을 시작할 때)** and **When focus ends (집중이 끝날 때)**. Leave a field empty to do nothing for that event.
4. Click **Try running (실행해 보기)** to check that the shortcut runs.

## When shortcuts run

| Event | Shortcut |
|---|---|
| Focus starts, either manually or automatically after a break | Start |
| You choose “Focus for 10 more minutes (10분 더 집중)” | Start |
| Focus time runs out | End |
| You skip, reset, or quit during focus | End |

- Pausing, resuming, and starting a break do not run shortcuts. If focus starts automatically after a break ends or is skipped, the start shortcut runs.
- When focus time runs out, the end shortcut runs first. Choosing “Start break (휴식 시작)” afterward does not run it again.
- Shortcuts run at the start and end of focus even with transition support (전환 관리) turned off.

## How it works and limitations

- The app opens `shortcuts://run-shortcut?name=<이름>` to run a shortcut. `<이름>` represents its name. This integration does not change the app's entitlements.
- The URL is opened without requesting that Shortcuts come to the foreground. Shortcuts may still open its own windows, and once launched, it remains running.
- If the named shortcut does not exist, Shortcuts displays an error. Correct the name or clear the field.
- Morrowisp cannot tell whether a shortcut has finished or succeeded. If end and start requests arrive almost together—for example, when you choose another 10 minutes immediately after focus ends—the later request may finish first.
- Quitting during focus delays exit briefly, for up to two seconds, while the end shortcut's launch request is handed off.
- A force quit or crash does not run the end shortcut. If your shortcut enabled Do Not Disturb, you will need to turn it off yourself.
