#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="$ROOT/build/Dynamic Bangs.app"
OUT_DIR="$ROOT/build/release"

if [[ "${1:-}" == "--rebuild" || ! -d "$APP_PATH" ]]; then
  echo "Building Dynamic Bangs.app..."
  python3 "$ROOT/Tools/build-local.py"
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "Error: $APP_PATH not found." >&2
  exit 1
fi

codesign --verify --deep --strict "$APP_PATH"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
DMG_NAME="Dynamic-Bangs-${VERSION}-macOS-arm64.dmg"
DMG_PATH="$OUT_DIR/$DMG_NAME"
mkdir -p "$OUT_DIR"

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/dynamic-bangs-dmg.XXXXXX")"
MOUNT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dynamic-bangs-mnt.XXXXXX")"
DRAFT_DIR="$(mktemp -d "$OUT_DIR/.dynamic-bangs-dmg.XXXXXX")"
DRAFT_PATH="$DRAFT_DIR/$DMG_NAME"
cleanup() {
  if mount | grep -q "$MOUNT_DIR"; then
    hdiutil detach "$MOUNT_DIR" -quiet || hdiutil detach "$MOUNT_DIR" -force -quiet || true
  fi
  rm -rf "$STAGE" "$MOUNT_DIR" "$DRAFT_DIR"
}
trap cleanup EXIT

ditto "$APP_PATH" "$STAGE/Dynamic Bangs.app"
ln -s /Applications "$STAGE/Applications"
mkdir "$STAGE/许可证"
cp "$ROOT/LICENSE" "$STAGE/许可证/CoteDOs-MIT.txt"
cp "$ROOT/Vendor/mediaremote-adapter/LICENSE" "$STAGE/许可证/mediaremote-adapter-BSD-3-Clause.txt"

cat > "$STAGE/安装说明.txt" <<'EOF'
Dynamic Bangs 安装说明
=====================

1. 将 "Dynamic Bangs.app" 拖入右侧的 "Applications"（应用程序）文件夹。
2. 此体验版使用临时签名。若 macOS 首次打开时提示无法验证开发者，请核对文件来源，再参照 Apple 支持指南。
   https://support.apple.com/zh-cn/102445
3. 双击屏幕顶部刘海可展开工作台。

适用于搭载 Apple 芯片、运行 macOS 14 或更高版本的 Mac。实时频谱需要 macOS 14.4 和系统音频录制授权。
Dynamic Bangs 沿用 CoteDOs 的应用标识和数据目录。已安装 CoteDOs 时，请择一运行。
随包许可证位于“许可证”文件夹。
EOF

hdiutil create \
  -volname "Dynamic Bangs" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$DRAFT_PATH"

hdiutil verify "$DRAFT_PATH"
hdiutil attach "$DRAFT_PATH" -nobrowse -noautoopen -readonly -mountpoint "$MOUNT_DIR" -quiet
codesign --verify --deep --strict "$MOUNT_DIR/Dynamic Bangs.app"
cmp "$ROOT/LICENSE" "$MOUNT_DIR/许可证/CoteDOs-MIT.txt"
cmp "$ROOT/Vendor/mediaremote-adapter/LICENSE" "$MOUNT_DIR/许可证/mediaremote-adapter-BSD-3-Clause.txt"
hdiutil detach "$MOUNT_DIR" -quiet
mv -f "$DRAFT_PATH" "$DMG_PATH"

echo ""
echo "DMG ready: $DMG_PATH"
ls -lh "$DMG_PATH"
shasum -a 256 "$DMG_PATH"
