#!/bin/bash
# update-e2e.sh — 자동 업데이트가 실제로 도는지 이 Mac 에서 한 바퀴 돌려 본다. 아무것도 올리지 않는다.
#
#   bash scripts/update-e2e.sh
#
# 시험용 번들 id(Jeong.Pomodoro.updatetest)와 그 자리에서 만든 일회용 서명 키로 세 버전(0.9.0, 0.9.1, 0.9.2)을
# 빌드하고, localhost 에 업데이트 목록을 띄운 뒤 두 가지를 본다.
#   1) 0.9.0 을 켠다 → 0.9.1 을 스스로 받는다. 창이 열려 있으면 받아 두기만 하고(스스로 설치하지 않음),
#      앱이 끝날 때 설치된다. (창이 없으면 그 자리에서 스스로 설치하고 다시 켜진다.)
#   2) 0.9.1 을 숨긴 채(창 없음)로 켠다 → 0.9.2 를 받아, 조용한 채로 잠시 지나면 스스로 설치하고 다시 켜진다.
# 업데이트 목록은 scripts/release.sh 와 같은 선택(전체 zip 만)으로 만든다.
# 쓰고 있는 Pomodoro, /Applications 의 앱, 키체인, 실제 업데이트 주소는 건드리지 않는다.
# 시험용 앱이 메뉴 바에 잠깐 뜨고, 처음이면 "집중 기록" 창과 알림 권한 물음이 한 번 뜰 수 있다.
# 시험은 내장 디스크(~/Library/Developer/Pomodoro-build/update-e2e)에서 한다. 저장소가 외장 디스크에 있어도 그렇다 —
# 외장 디스크에 놓인 앱을 Sparkle 이 바꾸려 하면 macOS 가 "이동식 볼륨의 파일에 접근" 허락을 묻고, 답할 때까지 설치가 멈춘다
# (임시 서명은 빌드마다 달라서 매번 다시 묻는다).
# 남는 것: 위 폴더(다음 실행 때 옆으로 옮긴다), ~/Library/Containers/Jeong.Pomodoro.updatetest (시험용 앱의 자료).
# 필요한 것: Xcode, python3, ed25519 를 아는 openssl(Homebrew 의 openssl 3).
# 어떻게 불렸든(bash scripts/…, sh …) macOS 의 /bin/bash 로 돈다. PATH 에 먼저 잡히는 Homebrew 의 bash(5.x)는
# CoreFoundation 을 쓰는 gettext 에 물려 있어, 갈라져 나온 하위 셸이 로캘을 되돌리다가 드물게 죽는다
# (2026-10-10: 릴리스 예행이 테스트 직후 SIGSEGV 로 끝남).
[ "${BASH:-}" = /bin/bash ] || exec /bin/bash "$0" "$@"
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
TEST_ID="Jeong.Pomodoro.updatetest"
PORT="${UPDATE_E2E_PORT:-18731}"
FEED="http://localhost:$PORT"
SETTLE=5   # 시험에서는 조용함을 5초만 기다린다 (앱의 기본값은 60초)
BUILD_HOME="${POMODORO_BUILD_HOME:-$HOME/Library/Developer/Pomodoro-build}"
WORK="$BUILD_HOME/update-e2e"
BIN="$BUILD_HOME/dd/SourcePackages/artifacts/sparkle/Sparkle/bin"
say() { printf '\n== %s\n' "$*"; }
die() { printf 'update-e2e: 실패 — %s\n' "$*" >&2; exit 1; }
OPENSSL="${OPENSSL:-}"
[ -n "$OPENSSL" ] || { [ -x /opt/homebrew/bin/openssl ] && OPENSSL=/opt/homebrew/bin/openssl; } || OPENSSL="$(command -v openssl || true)"
[ -n "$OPENSSL" ] || die "openssl 이 없습니다"

! pgrep -f "update-e2e.*/install/Pomodoro.app/Contents/MacOS/Pomodoro" > /dev/null || die "시험용 앱이 이미 떠 있습니다. 끈 뒤 다시 합니다"
[ ! -e "$WORK" ] || mv "$WORK" "$WORK.$(date +%Y%m%d-%H%M%S).old"
mkdir -p "$WORK/keys" "$WORK/feed" "$WORK/install"
chmod 700 "$WORK/keys"
APP="$WORK/install/Pomodoro.app"
EXE="$APP/Contents/MacOS/Pomodoro"
SERVER_PID=""
app_pids() { pgrep -f "$EXE" || true; }
version() { /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || true; }
stop_app() { for p in $(app_pids); do kill "$p" 2>/dev/null || true; done; }
cleanup() {
  stop_app
  [ -z "$SERVER_PID" ] || kill "$SERVER_PID" 2>/dev/null || true
}
trap cleanup EXIT

say "일회용 서명 키 (키체인을 쓰지 않는다)"
[ -x "$BIN/generate_appcast" ] || xcodebuild -project Pomodoro.xcodeproj -scheme Pomodoro -derivedDataPath "$BUILD_HOME/dd" -resolvePackageDependencies > "$WORK/resolve.log" 2>&1 || die "패키지를 받지 못했습니다: $WORK/resolve.log"
"$OPENSSL" genpkey -algorithm ed25519 -outform DER -out "$WORK/keys/priv.der" 2>/dev/null || die "openssl 이 ed25519 키를 만들지 못했습니다 ($OPENSSL)"
"$OPENSSL" pkey -inform DER -in "$WORK/keys/priv.der" -pubout -outform DER -out "$WORK/keys/pub.der" 2>/dev/null || die "공개 키를 꺼내지 못했습니다"
# DER 의 마지막 32바이트가 각각 개인 키의 씨앗과 공개 키다.
tail -c 32 "$WORK/keys/priv.der" | base64 > "$WORK/keys/seed.b64"
PUB="$(tail -c 32 "$WORK/keys/pub.der" | base64)"
[ -n "$PUB" ] || die "공개 키가 비었습니다"
chmod 600 "$WORK/keys/"*

say "시험용 Info.plist (localhost 의 http 만 더 허용)"
cp Config/Info.plist "$WORK/Info-e2e.plist"
/usr/libexec/PlistBuddy -c 'Add :NSAppTransportSecurity dict' -c 'Add :NSAppTransportSecurity:NSAllowsLocalNetworking bool true' "$WORK/Info-e2e.plist"

build() { # build <버전> <빌드 번호>
  xcodebuild -project Pomodoro.xcodeproj -scheme Pomodoro -configuration Release -derivedDataPath "$WORK/dd" build \
    PRODUCT_BUNDLE_IDENTIFIER="$TEST_ID" MARKETING_VERSION="$1" CURRENT_PROJECT_VERSION="$2" \
    POMODORO_ED_PUBLIC_KEY="$PUB" POMODORO_FEED_URL="$FEED/appcast.xml" INFOPLIST_FILE="$WORK/Info-e2e.plist" \
    > "$WORK/build-$1.log" 2>&1 || die "$1 빌드 실패: $WORK/build-$1.log"
  echo "빌드 $1 ($2)"
}
publish() { # publish <버전> — 방금 빌드한 것을 업데이트 목록에 올린다 (release.sh 와 같은 선택)
  ditto -c -k --sequesterRsrc --keepParent "$WORK/dd/Build/Products/Release/Pomodoro.app" "$WORK/feed/Pomodoro-$1.zip"
  "$BIN/generate_appcast" --ed-key-file "$WORK/keys/seed.b64" --download-url-prefix "$FEED/" --maximum-deltas 0 \
    -o "$WORK/feed/appcast.xml" "$WORK/feed" > "$WORK/appcast-$1.log" 2>&1 || die "appcast 생성 실패: $WORK/appcast-$1.log"
}
wait_for() { # wait_for <초> <설명> <명령...> — 명령이 참이 될 때까지 기다린다. 안 되면 실패로 끝낸다
  local limit="$1" what="$2"; shift 2
  local t=0
  until "$@"; do
    sleep 1; t=$((t + 1))
    [ "$t" -lt "$limit" ] || die "$what (${limit}초 안에 일어나지 않음)"
  done
}
within() { # within <초> <명령...> — 그 시간 안에 참이 되면 0, 아니면 1 (실패로 끝내지 않는다)
  local limit="$1"; shift
  local t=0
  until "$@"; do
    sleep 1; t=$((t + 1))
    [ "$t" -lt "$limit" ] || return 1
  done
}
downloaded() { grep -q "GET /$1 " "$WORK/http.log"; }
is_version() { [ "$(version)" = "$1" ]; }
running_as() { [ "$(version)" = "$1" ] && [ -n "$(app_pids)" ]; }
# 시험용 앱과, 그 묶음 안에서 도는 Sparkle 의 설치 도우미까지 모두 끝났는지
no_processes() { ! pgrep -f "$APP/" > /dev/null; }
# 시험용 앱의 설정은 지난 실행의 것이 남아 있다(마지막 확인 시각 등). 실행 인자로 옛날로 돌려 곧바로 확인하게 하고,
# 조용함을 기다리는 시간도 줄인다.
ARGS=(--args -SULastCheckTime '<date>2020-01-01T00:00:00Z</date>' -UpdateInstallSettleSeconds "$SETTLE")

say "빌드: 0.9.0 을 설치 자리에, 0.9.1 을 업데이트 목록에"
build 0.9.0 1
ditto "$WORK/dd/Build/Products/Release/Pomodoro.app" "$APP"
build 0.9.1 2
publish 0.9.1

say "업데이트 목록 서버 ($FEED)"
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$WORK/feed" > "$WORK/http.log" 2>&1 &
SERVER_PID=$!
wait_for 10 "서버가 뜨지 않음" curl -fs -o /dev/null "$FEED/appcast.xml"

say "1) 0.9.0 을 켠다 → 0.9.1 을 스스로 받는가"
open -n "$APP" "${ARGS[@]}"
wait_for 60 "0.9.0 이 0.9.1 을 내려받지 않음" downloaded "Pomodoro-0.9.1.zip"
echo "내려받음"
# 조용하면(창 없음) 잠시 뒤 스스로 설치한다. 조용함 $SETTLE초 + 다시 재는 간격 10초 + 여유.
if within $((SETTLE + 30)) running_as 0.9.1; then
  echo "창이 없어서 스스로 설치하고 다시 켜졌다"
else
  is_version 0.9.0 || die "설치 자리의 버전이 이상함: '$(version)'"
  [ -n "$(app_pids)" ] || die "받아 둔 채 기다려야 할 앱이 꺼져 있음"
  echo "받아 두고 기다리는 중(창이 열려 있어 스스로 설치하지 않음) → 앱을 끝낸다"
  stop_app
  wait_for 30 "앱이 끝난 뒤에도 0.9.1 이 설치되지 않음" is_version 0.9.1
  echo "앱이 끝나자 설치됐다"
fi
stop_app
wait_for 30 "시험용 앱이나 설치 도우미가 끝나지 않음" no_processes
codesign --verify --deep --strict "$APP" || die "설치된 0.9.1 의 서명 확인 실패"

say "2) 0.9.1 을 숨긴 채로 켠다 → 0.9.2 를 스스로 설치하고 다시 켜지는가"
build 0.9.2 3
publish 0.9.2
open -n -j "$APP" "${ARGS[@]}"
wait_for 60 "0.9.1 이 0.9.2 를 내려받지 않음" downloaded "Pomodoro-0.9.2.zip"
wait_for 90 "0.9.1 이 스스로 0.9.2 로 바뀌어 다시 켜지지 않음" running_as 0.9.2
sleep 3
running_as 0.9.2 || die "다시 켜진 앱이 곧 꺼졌다"
codesign --verify --deep --strict "$APP" || die "설치된 0.9.2 의 서명 확인 실패"
echo "스스로 설치하고 다시 켜졌다 (0.9.2, pid $(app_pids | tr '\n' ' '))"

say "통과"
echo "서버가 받은 요청:"
grep GET "$WORK/http.log" | sed 's/^/  /' || true
