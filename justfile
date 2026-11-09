# Project commands. Output is kept short: builds log to build/logs/ and
# print the tail only on failure; tests report failures only.
# `just` lists everything.

# A failing command fails the recipe even when piped (e.g. into tail).
set shell := ["bash", "-euo", "pipefail", "-c"]

adb := env("HOME") / "Library/Android/sdk/platform-tools/adb"
app_id := "com.harshal.atharxa"
logs := "build/logs"

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
mac:
    @mkdir -p {{logs}}
    @flutter build macos --release > {{logs}}/mac.log 2>&1 && echo "built build/macos/Build/Products/Release/Atharxa.app" || (tail -30 {{logs}}/mac.log; exit 1)

# Build and (re)open the macOS release app
mac-open: mac
    @pkill -f "Atharxa.app/Contents/MacOS/Atharxa" || true
    @open build/macos/Build/Products/Release/Atharxa.app

# Build and install into /Applications (free, this Mac only; data is kept), then open it
mac-install: mac
    @pkill -f "Atharxa.app/Contents/MacOS/Atharxa" || true
    @sleep 1
    @rm -rf /Applications/Atharxa.app
    @ditto build/macos/Build/Products/Release/Atharxa.app /Applications/Atharxa.app
    @open /Applications/Atharxa.app
    @echo "installed /Applications/Atharxa.app"

# Run on macOS in debug (hot reload)
mac-run:
    flutter run -d macos

# Memory of the running macOS app (release builds only are meaningful)
mac-mem:
    @footprint $(pgrep -f "Atharxa.app/Contents/MacOS/Atharxa" | head -1) | grep phys_footprint: | head -1

# ---------------------------------------------------------------- Android

# Build the Android release APK (arm64)
apk:
    @mkdir -p {{logs}}
    @flutter build apk --release > {{logs}}/apk.log 2>&1 && grep "Built" {{logs}}/apk.log || (tail -30 {{logs}}/apk.log; exit 1)

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
all: phone mac-open

# Remove build output (keeps the AI engine download cache)
clean:
    @flutter clean > /dev/null && echo cleaned
