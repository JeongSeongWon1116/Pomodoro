#!/bin/bash
# release.sh — Pomodoro 릴리스를 만든다.
#
#   bash scripts/release.sh             테스트 → Release 빌드 → zip → 서명한 appcast. build/release/v<버전>/ 에 남기고 끝난다
#                                       (아무것도 올리지 않고, 설치하지도 않는다)
#   bash scripts/release.sh --publish   위 + GitHub 릴리스 v<버전> (태그는 origin/main 의 지금 커밋에 붙는다)
#   bash scripts/release.sh --install   위 + 이 Mac 의 /Applications/Pomodoro.app 을 새 빌드로 바꾸고 다시 켠다
#   (--publish 와 --install 은 함께 줄 수 있다. --allow-key-change 는 서명 키를 일부러 바꾼 릴리스에만 쓴다)
#
# 버전은 프로젝트의 MARKETING_VERSION 에서 읽는다. 올리기 전에 버전과 CHANGELOG.md 를 고쳐 main 에 넣어 둔다.
# 업데이트 서명 키는 키체인에 있다(처음 한 번 docs/RELEASE.md 의 "서명 키"). 이 스크립트는 키 값을 읽거나 출력하지 않는다.
# 빌드는 ~/Library/Developer/Pomodoro-build/dd 에 한다(POMODORO_BUILD_HOME 으로 바꿀 수 있다).
#   - Xcode 의 기본 DerivedData(Xcode 에서 실행 중인 앱이 쓰는 곳)를 건드리지 않는다.
#   - 저장소가 외장 디스크에 있어도 빌드는 내장 디스크에 둔다. 외장 디스크에서 앱을 띄우면(단위 테스트의 호스트 앱)
#     macOS 가 "이동식 볼륨의 파일에 접근" 허락을 묻고, 임시 서명은 빌드마다 달라서 매번 다시 묻는다.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
REPO="JeongSeongWon1116/Pomodoro"
BUNDLE_ID="Jeong.Pomodoro"
BUILD_HOME="${POMODORO_BUILD_HOME:-$HOME/Library/Developer/Pomodoro-build}"
DD="$BUILD_HOME/dd"
BIN="$DD/SourcePackages/artifacts/sparkle/Sparkle/bin"
PUBLISH=0; INSTALL=0; ALLOW_KEY_CHANGE=0
for arg in "$@"; do
  case "$arg" in
    --publish) PUBLISH=1 ;;
    --install) INSTALL=1 ;;
    --allow-key-change) ALLOW_KEY_CHANGE=1 ;;
    *) sed -n '2,12p' "$0"; exit 2 ;;
  esac
done
say() { printf '\n== %s\n' "$*"; }
die() { printf 'release: %s\n' "$*" >&2; exit 1; }
xcb() { xcodebuild -project Pomodoro.xcodeproj -scheme Pomodoro -derivedDataPath "$DD" "$@"; }
# project.pbxproj 글에서 빌드 설정 하나의 첫 값을 꺼낸다 (따옴표가 있든 없든).
pbx_setting() { sed -n "s/^[[:space:]]*$1 = \"\{0,1\}\([^\";]*\)\"\{0,1\};\$/\1/p" | head -1; }

say "버전과 서명 키"
mkdir -p "$BUILD_HOME" "$ROOT/build"
[ -x "$BIN/generate_appcast" ] || xcb -resolvePackageDependencies > "$BUILD_HOME/release-resolve.log" 2>&1 || die "패키지를 받지 못했습니다: $BUILD_HOME/release-resolve.log"
[ -x "$BIN/generate_appcast" ] && [ -x "$BIN/generate_keys" ] || die "Sparkle 도구가 없습니다: $BIN"
SETTINGS="$(xcb -configuration Release -showBuildSettings 2>"$BUILD_HOME/release-settings.log")" || die "빌드 설정을 읽지 못했습니다: $BUILD_HOME/release-settings.log"
setting() { printf '%s\n' "$SETTINGS" | awk -v k="$1" '$1 == k && $2 == "=" { sub(/^[^=]*= ?/, ""); print; exit }'; }
VERSION="$(setting MARKETING_VERSION)"; BUILD="$(setting CURRENT_PROJECT_VERSION)"; PUBKEY="$(setting POMODORO_ED_PUBLIC_KEY)"
[ -n "$VERSION" ] && [ -n "$BUILD" ] || die "버전을 읽지 못했습니다"
case "$BUILD" in (*[!0-9]*) die "빌드 번호가 숫자가 아닙니다: $BUILD" ;; esac
[ -n "$PUBKEY" ] || die "프로젝트에 업데이트 공개 키(POMODORO_ED_PUBLIC_KEY)가 없습니다. docs/RELEASE.md 의 '서명 키'를 먼저 합니다"
# 프로젝트의 공개 키와 키체인의 서명 키가 짝이 맞는지 본다. 어긋나면 이 릴리스는 어떤 앱에서도 설치되지 않는다.
KEYCHAIN_PUB="$("$BIN/generate_keys" -p 2>/dev/null || true)"
[ "$KEYCHAIN_PUB" = "$PUBKEY" ] || die "키체인의 서명 키와 프로젝트의 공개 키가 다릅니다(또는 키체인에 키가 없습니다)"
grep -q -F -- "## [$VERSION]" CHANGELOG.md || die "CHANGELOG.md 에 [$VERSION] 절이 없습니다"
echo "Pomodoro $VERSION ($BUILD)"

say "지난 릴리스와 견주기"
# 이미 설치된 앱은 지난 릴리스에 든 공개 키를 믿고, 빌드 번호가 더 커야만 업데이트로 본다.
[ "$PUBLISH" = 0 ] || git fetch -q --tags origin || die "태그를 받아 오지 못했습니다"
PREV_TAG="$(git tag --list 'v[0-9]*' --sort=-v:refname | head -1)"
if [ -n "$PREV_TAG" ]; then
  PREV_PBX="$(git show "$PREV_TAG:Pomodoro.xcodeproj/project.pbxproj")" || die "$PREV_TAG 의 프로젝트 파일을 읽지 못했습니다"
  PREV_BUILD="$(printf '%s\n' "$PREV_PBX" | pbx_setting CURRENT_PROJECT_VERSION)"
  PREV_KEY="$(printf '%s\n' "$PREV_PBX" | pbx_setting POMODORO_ED_PUBLIC_KEY)"
  echo "지난 릴리스 $PREV_TAG (빌드 ${PREV_BUILD:-?})"
  case "${PREV_BUILD:-x}" in (*[!0-9]*) die "$PREV_TAG 의 빌드 번호를 읽지 못했습니다" ;; esac
  [ "$BUILD" -gt "$PREV_BUILD" ] || die "빌드 번호($BUILD)가 지난 릴리스($PREV_BUILD)보다 커야 합니다. 같거나 작으면 설치된 앱이 업데이트로 보지 않습니다"
  if [ -n "$PREV_KEY" ] && [ "$PREV_KEY" != "$PUBKEY" ]; then
    [ "$ALLOW_KEY_CHANGE" = 1 ] || die "공개 키가 $PREV_TAG 와 다릅니다. 이미 설치된 앱은 이 릴리스를 받아들이지 않습니다. 일부러 바꾼 것이면 --allow-key-change"
    echo "주의: 공개 키가 $PREV_TAG 와 다릅니다 (--allow-key-change)"
  fi
else
  echo "지난 릴리스 없음(첫 릴리스)"
fi

if [ "$PUBLISH" = 1 ]; then
  say "올리기 전 확인"
  [ -z "$(git status --porcelain)" ] || die "작업 폴더에 커밋하지 않은 것이 있습니다"
  git fetch -q origin || die "origin 을 받아 오지 못했습니다"
  [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || die "HEAD 가 origin/main 과 다릅니다. main 을 받아 온 뒤 다시 합니다"
  ! git ls-remote --exit-code --tags origin "refs/tags/v$VERSION" > /dev/null 2>&1 || die "태그 v$VERSION 이 이미 있습니다"
  gh auth status > /dev/null 2>&1 || die "gh 로그인이 필요합니다"
fi

say "단위 테스트"
xcb -only-testing:PomodoroTests test > "$BUILD_HOME/release-test.log" 2>&1 || die "테스트 실패: $BUILD_HOME/release-test.log"
PASSED="$(LC_ALL=C grep -a -c "^Test case .* passed" "$BUILD_HOME/release-test.log" || true)"
[ "${PASSED:-0}" -gt 0 ] || die "통과한 테스트를 세지 못했습니다: $BUILD_HOME/release-test.log"
echo "$PASSED 건 통과"

say "Release 빌드 (arm64 + x86_64)"
xcb -configuration Release build ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO > "$BUILD_HOME/release-build.log" 2>&1 || die "빌드 실패: $BUILD_HOME/release-build.log"
APP="$DD/Build/Products/Release/Pomodoro.app"
PLIST="$APP/Contents/Info.plist"
read_plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST"; }
[ "$(read_plist CFBundleShortVersionString)" = "$VERSION" ] && [ "$(read_plist CFBundleVersion)" = "$BUILD" ] || die "빌드한 앱의 버전이 다릅니다"
[ "$(read_plist CFBundleIdentifier)" = "$BUNDLE_ID" ] || die "빌드한 앱의 번들 id 가 다릅니다"
[ "$(read_plist SUPublicEDKey)" = "$PUBKEY" ] || die "빌드한 앱에 공개 키가 들어가지 않았습니다"
codesign --verify --deep --strict "$APP" || die "코드 서명 확인 실패"
ARCHS_BUILT="$(lipo -archs "$APP/Contents/MacOS/Pomodoro")" || die "빌드한 앱의 아키텍처를 읽지 못했습니다"
case " $ARCHS_BUILT " in (*" arm64 "*) ;; (*) die "arm64 가 빠졌습니다: $ARCHS_BUILT" ;; esac
case " $ARCHS_BUILT " in (*" x86_64 "*) ;; (*) die "x86_64 가 빠졌습니다: $ARCHS_BUILT" ;; esac
echo "$ARCHS_BUILT"

say "묶음과 appcast"
OUT="$ROOT/build/release/v$VERSION"
[ ! -e "$OUT" ] || mv "$OUT" "$OUT.$(date +%Y%m%d-%H%M%S).old"
mkdir -p "$OUT"
ZIP="$OUT/Pomodoro-$VERSION.zip"
NOTES="$OUT/Pomodoro-$VERSION.md"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
# 릴리스 노트: CHANGELOG.md 의 이 버전 절
# (저장소 안의 파일을 가리키는 링크는 릴리스 쪽과 앱의 안내 창에서도 열리도록 그 버전의 전체 주소로 바꾼다)
awk -v h="## [$VERSION]" '/^## \[/ { on = (index($0, h) == 1); next } on' CHANGELOG.md \
  | sed -E "s#\]\((docs/|Readme\.md|CHANGELOG\.md)#](https://github.com/$REPO/blob/v$VERSION/\1#g" > "$NOTES"
[ -s "$NOTES" ] || die "릴리스 노트가 비었습니다"
"$BIN/generate_appcast" --download-url-prefix "https://github.com/$REPO/releases/download/v$VERSION/" \
  --embed-release-notes --maximum-deltas 0 --link "https://github.com/$REPO" -o "$OUT/appcast.xml" "$OUT" \
  || die "appcast 를 만들지 못했습니다"
grep -q "sparkle:edSignature=" "$OUT/appcast.xml" || die "appcast 에 서명이 없습니다"
grep -q "<sparkle:version>$BUILD</sparkle:version>" "$OUT/appcast.xml" || die "appcast 의 버전이 다릅니다"
grep -q "<description" "$OUT/appcast.xml" || die "appcast 에 릴리스 노트가 들어가지 않았습니다"
ls -la "$OUT"

if [ "$PUBLISH" = 1 ]; then
  say "GitHub 릴리스 v$VERSION"
  gh release create "v$VERSION" "$ZIP" "$OUT/appcast.xml" --repo "$REPO" --target "$(git rev-parse HEAD)" \
    --title "Pomodoro $VERSION" --notes-file "$NOTES"
  # 앱이 보는 주소(최신 릴리스의 appcast)가 방금 올린 것을 돌려주는지 본다.
  LIVE="$(curl -fsSL "https://github.com/$REPO/releases/latest/download/appcast.xml")" || die "올렸지만 최신 릴리스의 appcast 를 받지 못했습니다. 릴리스 쪽을 확인합니다"
  printf '%s\n' "$LIVE" | grep -q "<sparkle:version>$BUILD</sparkle:version>" \
    || die "올렸지만 최신 릴리스의 appcast 가 이 버전이 아닙니다. 릴리스 쪽을 확인합니다"
  echo "올림: https://github.com/$REPO/releases/tag/v$VERSION"
fi

if [ "$INSTALL" = 1 ]; then
  say "이 Mac 에 설치"
  DEST="/Applications/Pomodoro.app"
  # 실행 중인 Pomodoro 를 정상 종료시킨다(진행 중인 세션은 앱이 끝내면서 기록한다). 강제로 죽이지 않는다.
  QUIT="$BUILD_HOME/quit-running.swift"
  cat > "$QUIT" <<'SWIFT'
import AppKit
let apps = NSRunningApplication.runningApplications(withBundleIdentifier: CommandLine.arguments[1])
apps.forEach { _ = $0.terminate() }
let deadline = Date().addingTimeInterval(15)
while Date() < deadline, apps.contains(where: { !$0.isTerminated }) { RunLoop.current.run(until: Date().addingTimeInterval(0.2)) }
exit(apps.contains(where: { !$0.isTerminated }) ? 1 : 0)
SWIFT
  swift "$QUIT" "$BUNDLE_ID" || die "실행 중인 Pomodoro 가 끝나지 않았습니다. 직접 끈 뒤 다시 합니다"
  # 끄는 순간, 앱이 받아 둔 업데이트가 있으면 Sparkle 의 설치 도우미가 앱을 바꾸기 시작한다. 그것이 끝나기를 기다린다
  # (기다리지 않으면 반쯤 바뀐 앱을 옮기거나, 방금 넣은 빌드가 덮일 수 있다).
  HELPERS='Pomodoro\.app/Contents/Frameworks/Sparkle\.framework'
  waited=0
  while pgrep -f "$HELPERS" | while read -r pid; do ps -o command= -p "$pid" | grep -v -q "/update-e2e/" && echo "$pid"; done | grep -q .; do
    [ "$waited" -lt 90 ] || die "Sparkle 설치 도우미가 끝나지 않습니다. 끝난 뒤 다시 합니다"
    sleep 1; waited=$((waited + 1))
  done
  if [ -e "$DEST" ]; then
    OLD_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$DEST/Contents/Info.plist" 2>/dev/null || echo old)"
    # 지우지 않고 옮겨 둔다. 이름 끝을 .app 이 아니게 해서, macOS 가 이것을 또 하나의 Pomodoro 로 보고
    # (Spotlight, 로그인 항목 등에서) 예전 앱을 띄우는 일이 없게 한다. 되돌리려면 이름을 Pomodoro.app 으로 바꿔 /Applications 에 넣는다.
    KEEP="$BUILD_HOME/replaced/Pomodoro-$OLD_VERSION-$(date +%Y%m%d-%H%M%S).app-replaced"
    mkdir -p "$(dirname "$KEEP")"
    mv "$DEST" "$KEEP"
    echo "예전 앱: $KEEP"
  fi
  ditto "$APP" "$DEST"
  codesign --verify --deep --strict "$DEST" || die "설치한 앱의 서명 확인 실패"
  [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$DEST/Contents/Info.plist")" = "$BUILD" ] || die "설치한 앱의 빌드 번호가 다릅니다"
  open "$DEST"
  echo "설치하고 켬: $DEST ($VERSION)"
fi

say "끝"
