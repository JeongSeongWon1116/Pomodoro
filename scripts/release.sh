#!/bin/bash
# release.sh — Pomodoro 릴리스를 만든다.
#
#   bash scripts/release.sh             테스트 → Release 빌드 → zip → 서명한 appcast. build/release/v<버전>/ 에 남기고 끝난다
#                                       (아무것도 올리지 않고, 설치하지도 않는다)
#   bash scripts/release.sh --publish   위 + GitHub 릴리스 v<버전> (태그는 origin/main 의 지금 커밋에 붙는다)
#   bash scripts/release.sh --install   위 + 이 Mac 의 /Applications/Pomodoro.app 을 새 빌드로 바꾸고 다시 켠다
#   (--publish 와 --install 은 함께 줄 수 있다)
#
# 버전은 프로젝트의 MARKETING_VERSION 에서 읽는다. 올리기 전에 버전과 CHANGELOG.md 를 고쳐 main 에 넣어 둔다.
# 업데이트 서명 키는 키체인에 있다(처음 한 번 docs/RELEASE.md 의 "서명 키"). 이 스크립트는 키 값을 읽거나 출력하지 않는다.
# 빌드는 build/dd 에 한다 — Xcode 의 기본 DerivedData(Xcode 에서 실행 중인 앱이 쓰는 곳)를 건드리지 않는다.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
REPO="JeongSeongWon1116/Pomodoro"
BUNDLE_ID="Jeong.Pomodoro"
DD="$ROOT/build/dd"
BIN="$DD/SourcePackages/artifacts/sparkle/Sparkle/bin"
PUBLISH=0; INSTALL=0
for arg in "$@"; do
  case "$arg" in
    --publish) PUBLISH=1 ;;
    --install) INSTALL=1 ;;
    *) sed -n '2,13p' "$0"; exit 2 ;;
  esac
done
say() { printf '\n== %s\n' "$*"; }
die() { printf 'release: %s\n' "$*" >&2; exit 1; }
xcb() { xcodebuild -project Pomodoro.xcodeproj -scheme Pomodoro -derivedDataPath "$DD" "$@"; }

say "버전과 서명 키"
[ -x "$BIN/generate_appcast" ] || xcb -resolvePackageDependencies > /dev/null
[ -x "$BIN/generate_appcast" ] || die "Sparkle 도구가 없습니다: $BIN"
SETTINGS="$(xcb -configuration Release -showBuildSettings 2>/dev/null)"
setting() { printf '%s\n' "$SETTINGS" | awk -v k="$1" '$1 == k && $2 == "=" { sub(/^[^=]*= ?/, ""); print; exit }'; }
VERSION="$(setting MARKETING_VERSION)"; BUILD="$(setting CURRENT_PROJECT_VERSION)"; PUBKEY="$(setting POMODORO_ED_PUBLIC_KEY)"
[ -n "$VERSION" ] && [ -n "$BUILD" ] || die "버전을 읽지 못했습니다"
[ -n "$PUBKEY" ] || die "프로젝트에 업데이트 공개 키(POMODORO_ED_PUBLIC_KEY)가 없습니다. docs/RELEASE.md 의 '서명 키'를 먼저 합니다"
# 앱이 믿는 공개 키와 키체인의 서명 키가 짝이 맞는지 본다. 어긋나면 이 릴리스는 어떤 앱에서도 설치되지 않는다.
KEYCHAIN_PUB="$("$BIN/generate_keys" -p 2>/dev/null || true)"
[ "$KEYCHAIN_PUB" = "$PUBKEY" ] || die "키체인의 서명 키와 프로젝트의 공개 키가 다릅니다(또는 키체인에 키가 없습니다)"
grep -q "^## \[$VERSION\]" CHANGELOG.md || die "CHANGELOG.md 에 [$VERSION] 절이 없습니다"
echo "Pomodoro $VERSION ($BUILD)"

if [ "$PUBLISH" = 1 ]; then
  say "올리기 전 확인"
  [ -z "$(git status --porcelain)" ] || die "작업 폴더에 커밋하지 않은 것이 있습니다"
  git fetch -q origin
  [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || die "HEAD 가 origin/main 과 다릅니다. main 을 받아 온 뒤 다시 합니다"
  ! git ls-remote --exit-code --tags origin "refs/tags/v$VERSION" > /dev/null 2>&1 || die "태그 v$VERSION 이 이미 있습니다"
  gh auth status > /dev/null 2>&1 || die "gh 로그인이 필요합니다"
fi

say "단위 테스트"
xcb -only-testing:PomodoroTests test > "$ROOT/build/release-test.log" 2>&1 || die "테스트 실패: build/release-test.log"
LC_ALL=C grep -a -c "^Test case .* passed" "$ROOT/build/release-test.log" | sed 's/$/ 건 통과/'

say "Release 빌드 (arm64 + x86_64)"
xcb -configuration Release build ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO > "$ROOT/build/release-build.log" 2>&1 || die "빌드 실패: build/release-build.log"
APP="$DD/Build/Products/Release/Pomodoro.app"
PLIST="$APP/Contents/Info.plist"
read_plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST"; }
[ "$(read_plist CFBundleShortVersionString)" = "$VERSION" ] && [ "$(read_plist CFBundleVersion)" = "$BUILD" ] || die "빌드한 앱의 버전이 다릅니다"
[ "$(read_plist CFBundleIdentifier)" = "$BUNDLE_ID" ] || die "빌드한 앱의 번들 id 가 다릅니다"
[ "$(read_plist SUPublicEDKey)" = "$PUBKEY" ] || die "빌드한 앱에 공개 키가 들어가지 않았습니다"
codesign --verify --deep --strict "$APP" || die "코드 서명 확인 실패"
lipo -archs "$APP/Contents/MacOS/Pomodoro"

say "묶음과 appcast"
OUT="$ROOT/build/release/v$VERSION"
[ ! -e "$OUT" ] || mv "$OUT" "$OUT.$(date +%Y%m%d-%H%M%S).old"
mkdir -p "$OUT"
ZIP="$OUT/Pomodoro-$VERSION.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
# 릴리스 노트: CHANGELOG.md 의 이 버전 절
# (저장소 안의 파일을 가리키는 링크는 릴리스 쪽과 앱의 안내 창에서도 열리도록 전체 주소로 바꾼다)
awk -v v="$VERSION" '/^## \[/ { on = ($0 ~ "^## \\[" v "\\]") ; next } on' CHANGELOG.md \
  | sed -E "s#\]\((docs/|Readme\.md|CHANGELOG\.md)#](https://github.com/$REPO/blob/main/\1#g" > "$OUT/Pomodoro-$VERSION.md"
[ -s "$OUT/Pomodoro-$VERSION.md" ] || die "릴리스 노트가 비었습니다"
"$BIN/generate_appcast" --download-url-prefix "https://github.com/$REPO/releases/download/v$VERSION/" \
  --embed-release-notes --maximum-deltas 0 --link "https://github.com/$REPO" -o "$OUT/appcast.xml" "$OUT"
grep -q "sparkle:edSignature=" "$OUT/appcast.xml" || die "appcast 에 서명이 없습니다"
grep -q "<sparkle:version>$BUILD</sparkle:version>" "$OUT/appcast.xml" || die "appcast 의 버전이 다릅니다"
ls -la "$OUT"

if [ "$PUBLISH" = 1 ]; then
  say "GitHub 릴리스 v$VERSION"
  gh release create "v$VERSION" "$ZIP" "$OUT/appcast.xml" --repo "$REPO" --target "$(git rev-parse HEAD)" \
    --title "Pomodoro $VERSION" --notes-file "$OUT/Pomodoro-$VERSION.md"
  # 앱이 보는 주소(최신 릴리스의 appcast)가 방금 올린 것을 돌려주는지 본다.
  curl -fsSL "https://github.com/$REPO/releases/latest/download/appcast.xml" | grep -q "<sparkle:version>$BUILD</sparkle:version>" \
    || die "올렸지만 최신 릴리스의 appcast 가 이 버전이 아닙니다. 릴리스 쪽을 확인합니다"
  echo "올림: https://github.com/$REPO/releases/tag/v$VERSION"
fi

if [ "$INSTALL" = 1 ]; then
  say "이 Mac 에 설치"
  DEST="/Applications/Pomodoro.app"
  # 실행 중인 Pomodoro 를 정상 종료시킨다(진행 중인 세션은 앱이 끝내면서 기록한다). 강제로 죽이지 않는다.
  QUIT="$ROOT/build/quit-running.swift"
  cat > "$QUIT" <<'SWIFT'
import AppKit
let apps = NSRunningApplication.runningApplications(withBundleIdentifier: CommandLine.arguments[1])
apps.forEach { _ = $0.terminate() }
let deadline = Date().addingTimeInterval(15)
while Date() < deadline, apps.contains(where: { !$0.isTerminated }) { RunLoop.current.run(until: Date().addingTimeInterval(0.2)) }
exit(apps.contains(where: { !$0.isTerminated }) ? 1 : 0)
SWIFT
  swift "$QUIT" "$BUNDLE_ID" || die "실행 중인 Pomodoro 가 끝나지 않았습니다. 직접 끈 뒤 다시 합니다"
  if [ -e "$DEST" ]; then
    KEEP="$ROOT/build/replaced/Pomodoro-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$DEST/Contents/Info.plist" 2>/dev/null || echo old)-$(date +%Y%m%d-%H%M%S).app"
    mkdir -p "$(dirname "$KEEP")"
    mv "$DEST" "$KEEP"   # 지우지 않고 옮겨 둔다
    echo "예전 앱: $KEEP"
  fi
  ditto "$APP" "$DEST"
  codesign --verify --deep --strict "$DEST" || die "설치한 앱의 서명 확인 실패"
  open "$DEST"
  echo "설치하고 켬: $DEST ($VERSION)"
fi

say "끝"
