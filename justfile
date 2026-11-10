# Project commands. Output is kept short: builds log to build/logs/ and
# print the tail only on failure; tests report failures only.
# `just` lists everything.

# A failing command fails the recipe even when piped (e.g. into tail).
set shell := ["bash", "-euo", "pipefail", "-c"]

# The product name and app id (on the rename checklist in CLAUDE.md).
app_name := "Atharxa"
app_id := "com.harshal.atharxa"

adb := env("HOME") / "Library/Android/sdk/platform-tools/adb"
logs := "build/logs"
mac_app := "build/macos/Build/Products/Release/" + app_name + ".app"
mac_proc := app_name + ".app/Contents/MacOS/" + app_name
installed := "/Applications/" + app_name + ".app"
version := `grep "^version:" pubspec.yaml | sed "s/version: *//; s/+.*//"`

# List the commands
default:
    @just --list --unsorted

# ---------------------------------------------------------------- checks

# Format lib and test (page width 120)
fmt:
    @dart format lib test | tail -1

# Analyze (must be clean)
analyze:
    @flutter analyze 2>&1 | tail -3

# Run tests: all, or the given files/dirs (e.g. `just test test/db_test.dart`); failures only
test *paths:
    @flutter test -r failures-only {{paths}}

# Run tests whose name contains TEXT (e.g. `just test-name "AI models"`)
test-name text *paths:
    @flutter test -r failures-only --plain-name "{{text}}" {{paths}}

# Refresh screenshot goldens (all of test/screens, or the given files)
goldens *paths:
    @flutter test -r failures-only --update-goldens {{ if paths == "" { "test/screens" } else { paths } }} && echo "goldens updated"

# Before committing: format, analyze, full test suite
check: fmt analyze test

# ---------------------------------------------------------------- macOS

# Build the macOS release app
mac: (_build "mac" "macos")

# Build, install into /Applications (free, this Mac only; data is kept) and open it
mac-install: mac _mac-quit
    @rm -rf {{installed}}
    @ditto {{mac_app}} {{installed}}
    @open {{installed}}
    @echo "installed {{installed}}"

# Run on macOS in debug (hot reload)
mac-run:
    flutter run -d macos

# Memory of the running macOS app (release builds only are meaningful)
mac-mem:
    @footprint $(pgrep -f "{{mac_proc}}" | head -1) | grep phys_footprint: | head -1

# Quit the running app the normal way (it saves and syncs) and wait until it has exited
_mac-quit:
    @osascript -e 'quit app id "{{app_id}}"' > /dev/null 2>&1 || true
    @for _ in $(seq 50); do pgrep -f "{{mac_proc}}" > /dev/null || exit 0; sleep 0.1; done; pkill -f "{{mac_proc}}" || true

# ---------------------------------------------------------------- Android

# Build the Android release APK (arm64)
apk: (_build "apk" "apk")

# Build the APK and copy it to dist/<app>-<version>.apk, ready to share or install
apk-file: apk
    @mkdir -p dist
    @cp build/app/outputs/flutter-apk/app-release.apk dist/{{app_name}}-{{version}}.apk
    @echo "dist/{{app_name}}-{{version}}.apk ($(du -h dist/{{app_name}}-{{version}}.apk | cut -f1))"

# Build, install on the connected phone and open the app
phone: apk
    @{{adb}} install -r build/app/outputs/flutter-apk/app-release.apk | tail -1
    @{{adb}} shell monkey -p {{app_id}} -c android.intent.category.LAUNCHER 1 > /dev/null 2>&1
    @echo "opened on $({{adb}} shell getprop ro.product.model)"

# Run on the connected phone in debug
phone-run:
    flutter run -d $({{adb}} devices | sed -n 2p | cut -f1)

# Connected Android devices
devices:
    @{{adb}} devices -l | tail -n +2

# The app's recent log lines on the phone (errors and Flutter output)
phone-log lines="60":
    @{{adb}} logcat -d -v time --pid=$({{adb}} shell pidof {{app_id}}) | grep -E "flutter|E/|FATAL" | tail -{{lines}}

# ---------------------------------------------------------------- both

# Build and install on the phone and the Mac
all: phone mac-install

# Remove build output (keeps the AI engine download cache)
clean:
    @flutter clean > /dev/null && echo cleaned

# `flutter build <target> --release`, logged to build/logs/<name>.log; prints the tail on failure
_build name target:
    @mkdir -p {{logs}}
    @flutter build {{target}} --release > {{logs}}/{{name}}.log 2>&1 && (grep -h "✓ Built" {{logs}}/{{name}}.log || echo "built {{name}}") || (tail -30 {{logs}}/{{name}}.log; exit 1)
