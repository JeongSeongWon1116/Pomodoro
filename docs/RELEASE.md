[한국어](RELEASE.ko.md)

# Releases and automatic updates

Pomodoro is distributed through GitHub Releases. Installed copies use [Sparkle](https://sparkle-project.org) to download new versions. Installation happens when the user requests it or quits with an update ready.

This guide preserves the original commands, paths, and keys. `/Volumes/C/project/Pomodoro` is the original maintainer's checkout path; substitute your own checkout location when running the commands. Placeholders such as `<버전>` (version) and `<파일>` (file) need your own values. App controls are currently in Korean.

## Update behavior

- The app checks `https://github.com/JeongSeongWon1116/Pomodoro/releases/latest/download/appcast.xml`, the feed attached to the latest release, every six hours. It also checks at launch if six hours have passed since the last check.
- It downloads the new zip and installs it **only if its EdDSA signature matches the public key embedded in the app**. The public key is in the `POMODORO_ED_PUBLIC_KEY` build setting; the matching signing key is in the release Mac's Keychain.
- Installation quits and reopens the app. A downloaded update **does not install on its own while the app remains open**. A red dot appears at the upper right of the menu bar icon, and the popover shows “New version x.y.z (새 버전 x.y.z)” and **Update (업데이트)**. Clicking it installs and reopens the app (`HeldUpdate`, `UpdateController.performIndicatedUpdate`), including during focus; the session is recorded as it would be on quitting. If the user quits without clicking, Sparkle's installation helper waits for exit and installs then. TODO: Verify logout and restart behavior; the helper may exit first, leaving the update to be downloaded again at the next launch. Through 1.2.1, updates could install automatically after roughly a minute with the timer idle and all windows closed. That behavior was removed in 1.2.2.
- With an update ready, **Settings > General > Updates (설정 > 일반 > 업데이트)** also shows the downloaded version and **Install and relaunch now (지금 설치하고 다시 켜기)**, which performs the same action. Sparkle does not check again in this state: “Check now” is unavailable, and newer versions are found only after installing the held version. If the app has not exited 30 seconds after installation starts, for example because the helper failed, the button becomes available again.
- Settings also provides automatic-check controls and **Check now (지금 확인)**. Turning automatic checks off also disables downloads, following Sparkle's rules. When checks are on, updates are always downloaded. The separate automatic-download-and-install switch from 1.2.1 was removed; any stored disabled value is re-enabled on launch (`preferDownloadingUpdates`).
- Updates that cannot install immediately use the same dot. Clicking **Update** brings Sparkle's guidance window forward. This includes updates Sparkle cannot download automatically (information-only updates or major upgrades), an existing installer flow, and installation deferred for an administrator password. The app does not show that window on its own at launch.
- Development (Debug) builds run from Xcode and unit tests do not check for updates.

The app is sandboxed. Updating adds two kinds of entitlement in `Pomodoro/Pomodoro.entitlements`: outgoing network access (`network.client`) and communication with Sparkle's installer helpers (two `mach-lookup` exceptions).

## Signing key setup

The original release notes record this setup as completed for this repository on 2026-10-10. The signing key stays in the releaser's Keychain; only the public key belongs in the repository. The following procedure is for creating a key when needed, such as on another release Mac or after losing the key.

1. Resolve the package to obtain its tools. Skip this if `~/Library/Developer/Pomodoro-build/dd` is already available.

   ```bash
   cd /Volumes/C/project/Pomodoro && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Pomodoro.xcodeproj -scheme Pomodoro -derivedDataPath ~/Library/Developer/Pomodoro-build/dd -resolvePackageDependencies
   ```

2. Generate a key. Allow Keychain storage when prompted. The output includes a public-key line, which is not secret.

   ```bash
   ~/Library/Developer/Pomodoro-build/dd/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys
   ```

3. Put the public key in both `POMODORO_ED_PUBLIC_KEY = "…";` settings (Debug and Release) in `Pomodoro.xcodeproj/project.pbxproj`, then commit it as part of release preparation. The original guide identifies the existing public key as the one created on 2026-10-10. To display the public key again, use `generate_keys -p`.

When packaging a release, Keychain asks whether `generate_appcast`, the signing tool, may use the key. Choose **Always Allow**. Choosing only Allow grants access once; subsequent runs wait at the packaging/appcast stage until the prompt is answered, including while the screen is locked. The original guide records this during the 2026-10-10 rehearsal.

Losing the key means installed copies will not accept releases signed with a replacement key; users would need to reinstall manually. Export a backup with `generate_keys -x <파일>` and keep it somewhere safe. Do not put that file in the repository or vault.

## Create a release

1. Update `MARKETING_VERSION` (display version) and `CURRENT_PROJECT_VERSION` (build number) in `project.pbxproj`. The build number **must increase** for update detection. Add a `## [버전] - 날짜` section to `CHANGELOG.md`, update the current source version in `Readme.md`, and land the release changes on main.
2. From a clean checkout of main, run:

   ```bash
   cd /Volumes/C/project/Pomodoro && bash scripts/release.sh
   ```

   This runs tests, builds Release for arm64 and x86_64, and creates a zip and signed `appcast.xml` in `build/release/v<버전>/`. It does not publish anything. Before building, it checks that the project's public key matches the Keychain signing key, the build number exceeds the previous release's (latest `v*` tag), and the public key matches that release's key. Installed apps trust the previous key. Use `--allow-key-change` only for an intentional key change.
3. Publish:

   ```bash
   cd /Volumes/C/project/Pomodoro && bash scripts/release.sh --publish
   ```

   This creates GitHub release `v<버전>` and attaches the zip and `appcast.xml`. It then checks that the app's feed URL returns this version. Installed copies download it within six hours, or when the user chooses Check now.
4. Add `--install` to replace `/Applications/Pomodoro.app` on the release Mac immediately. The script quits the running app normally. If Sparkle begins installing a held update, it waits and quits any relaunched app again, proceeding only after both the app and installer helper have been absent for five seconds. It moves the old app to `~/Library/Developer/Pomodoro-build/replaced/` with an `.app-replaced` suffix, installs and launches the new build, and checks that the running app is the newly installed copy. It finds running copies by bundle ID, so it also quits development builds launched from Xcode. If launch at login was enabled, check it in Settings > General after installation. This manual installation is unnecessary once an updating version is installed.

### Failure after publishing

If `--publish` creates the release but later verification or `--install` fails, the release and tag already exist. Repeating the same command stops because the tag exists.

- Retry installation only: `bash scripts/release.sh --install`. This rebuilds and installs the same version with a different ad hoc signature from the uploaded zip, which does not affect update behavior.
- Replace only the attachments: `gh release upload v<버전> build/release/v<버전>/Pomodoro-<버전>.zip build/release/v<버전>/appcast.xml --clobber`
- Start over, only if nobody has downloaded it yet: run `gh release delete v<버전> --cleanup-tag`, then repeat `--publish`.

The script builds in `~/Library/Developer/Pomodoro-build/dd`, configurable through `POMODORO_BUILD_HOME`. It leaves Xcode's default DerivedData alone. Keep build output on the internal disk even if the checkout is external, for the reasons below. The repository has no shared scheme; it relies on the `Pomodoro` scheme generated by `xcodebuild`.

## Verify the update flow

```bash
cd /Volumes/C/project/Pomodoro && bash scripts/update-e2e.sh
```

The test builds three versions with a test bundle ID and disposable key, using a localhost feed. It checks that an update downloads and remains held without installing, then installs on exit. It launches without windows and observes for 90 seconds after “holding update” appears in the app log, exceeding the former 60-second idle threshold plus the 10-second polling interval.

It also checks installation and relaunch through the same function as the Update button. It cannot click the actual button, so this case passes `-UpdateInstallHeldOnArrival YES`, which calls that function as soon as the update is held. The argument is read only from launch arguments, not saved settings, so it is not enabled in ordinary use. The feed uses full zip updates only, as releases do.

The test leaves the user's app, `/Applications`, Keychain, and real feed URL untouched. Run it after changing update code or the Sparkle version. TODO: Manually verify the dot, buttons, actual clicks, and clicking during focus. `PomodoroTests/UpdateTests.swift` covers the function invoked by the button. Download and installation timing appears in Console or `/usr/bin/log show`, under the app's `update` category; the test reads these logs too.

## Known limitations

- **No Apple notarization.** Releases are ad hoc signed because there is no Developer ID. macOS blocks the first launch until the user allows it; see [installation](../Readme.md#install). Sparkle-installed updates do not show that first-launch prompt.
- Ad hoc signatures differ with every build, so macOS may ask again for permissions tied to the signature. The original guide records a small sandbox test on macOS 27.0 on 2026-10-10: builds with the same bundle ID and different signatures read and wrote the same container without prompts and reused an earlier folder bookmark. TODO: Confirm history storage and Obsidian folder access across an actual Pomodoro release-to-release update. Notification permission and launch at login also remain unverified after an update.
- **An app on an external disk can stall during automatic updates.** macOS may ask the installer helper for permission to access removable volumes. Installation waits for an answer, and changing ad hoc signatures can cause another prompt on every update. The original guide records a stall with the screen locked on 2026-10-10. Keep the app in `/Applications` on the internal disk, and build unit tests and `update-e2e.sh` on the internal disk too.
- If Sparkle's update cycle ends while an update is held, for example because of a helper error or lost connection, the held installation action is no longer usable and the dot and button disappear. If the helper also exits, the next check downloads again. If only the connection ends and the helper stays alive, installation can still happen on quit, and the next scheduled check can take longer than six hours. The original guide cites Sparkle 2.10.0's `SPUUpdater.m` and `SPUUpdaterSettings.m`: the interval can extend to a week while installation is pending. Use Check now to continue in Sparkle's guidance window.
- Sparkle does not check for newer versions while an update is held. After installing a long-held update, another dot may appear for a newer version.
- The dot reflects the running app's state. Quitting with a downloaded update installs it, so the next launch has the new version and no dot. If the app only found an update it could not automatically download, the dot may stay absent after relaunch until the next check, within six hours.
- If the installation location is not writable, for example because another user installed the app, Sparkle asks for an administrator password. `release.sh --install` stops before quitting the app in that case. macOS App Management restrictions cannot be detected in advance; they may leave the app closed and the move blocked. The original guide says the actual installation on 2026-10-10 did not encounter this restriction.
- **Every future stable release must include `appcast.xml`.** The app reads the attachment on the latest release. Making a release without it the latest, for example through GitHub's web interface, silently breaks checks for installed copies. Create releases with `scripts/release.sh --publish`.
- Both scripts re-execute under macOS `/bin/bash`, regardless of how they are invoked. The original guide records a rare Homebrew bash 5.x subshell crash during locale restoration on 2026-10-10: exit code 139 after tests, with `gettext`'s `setlocale` → CoreFoundation in the crash report. Do not change shell locale variables inside the scripts; set them per command, as in `env LC_ALL=C grep …`.
