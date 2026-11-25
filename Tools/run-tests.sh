#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/dynamic-bangs-tests.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

run_suite() {
  local name="$1"
  shift
  echo "▶ $name"
  xcrun swiftc -swift-version 5 -parse-as-library -target arm64-apple-macos14.0 "$@" -o "$TMP/$name"
  "$TMP/$name"
}

run_suite TestMenuBarSafeArea \
  "$ROOT/Tools/TestMenuBarSafeArea.swift" \
  "$ROOT/CoteDOs/Window/MenuBarSafeArea.swift" \
  "$ROOT/CoteDOs/Window/NotchPlacement.swift"

run_suite TestInteractionState \
  "$ROOT/Tools/TestInteractionState.swift" \
  "$ROOT/CoteDOs/Window/ExpandedInteraction.swift"

run_suite TestDailyTask \
  "$ROOT/Tools/TestDailyTask.swift" \
  "$ROOT/CoteDOs/Tasks/DailyTasks.swift" \
  "$ROOT/CoteDOs/Core/Persistence.swift"

run_suite TestMusicSwipe \
  "$ROOT/Tools/TestMusicSwipe.swift" \
  "$ROOT/CoteDOs/NowPlaying/MusicSwipeRecognizer.swift"

run_suite TestNeteaseSnapshot \
  "$ROOT/Tools/TestNeteaseSnapshot.swift" \
  "$ROOT/CoteDOs/NowPlaying/NeteaseSnapshot.swift"

run_suite TestPresentationSettings \
  "$ROOT/Tools/TestPresentationSettings.swift" \
  "$ROOT/CoteDOs/Widgets/WidgetLayout.swift"

run_suite TestWidgetSystem \
  "$ROOT/Tools/TestWidgetSystem.swift" \
  "$ROOT/CoteDOs/Widgets/WidgetLayout.swift" \
  "$ROOT/CoteDOs/Widgets/WidgetStore.swift" \
  "$ROOT/CoteDOs/Widgets/SystemMetrics.swift" \
  "$ROOT/CoteDOs/Core/Persistence.swift"

run_suite TestQuickActions \
  "$ROOT/Tools/TestQuickActions.swift" \
  "$ROOT/CoteDOs/Notch/QuickActionsCatalog.swift" \
  "$ROOT/CoteDOs/Notch/QuickActionsView.swift" \
  "$ROOT/CoteDOs/Notch/NotchStyle.swift"

echo "All 8 test suites passed."
