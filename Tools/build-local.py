#!/usr/bin/env python3
"""Build the local Apple Silicon version with Xcode Command Line Tools."""
from pathlib import Path
import json
import plistlib
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build'
APP = BUILD / 'Dynamic Bangs.app'
contents = APP / 'Contents'
resources = contents / 'Resources'
executable = contents / 'MacOS/CoteDOs'
adapter_only = '--adapter-only' in sys.argv
if adapter_only and not executable.exists():
    raise SystemExit('Build Dynamic Bangs once before running --adapter-only.')
resources.mkdir(parents=True, exist_ok=True)
executable.parent.mkdir(exist_ok=True)
vendor = ROOT / 'Vendor/mediaremote-adapter'
framework = contents / 'Frameworks/MediaRemoteAdapter.framework'
framework.mkdir(parents=True, exist_ok=True)
objc = sorted(str(p) for p in (vendor / 'src').rglob('*.m') if '/test/' not in str(p))
subprocess.run(['xcrun', 'clang', '-dynamiclib', '-fobjc-arc', '-fvisibility=default',
    '-mmacosx-version-min=14.0', '-I' + str(vendor / 'include'), '-I' + str(vendor / 'src'),
    '-framework', 'Foundation', '-framework', 'AppKit', '-framework', 'UniformTypeIdentifiers',
    *objc, '-o', str(framework / 'MediaRemoteAdapter')], check=True)
(framework / 'Resources').mkdir(exist_ok=True)
(framework / 'Resources/Info.plist').write_bytes(plistlib.dumps(dict(
    CFBundleIdentifier='com.vandenbe.MediaRemoteAdapter', CFBundleName='MediaRemoteAdapter',
    CFBundleExecutable='MediaRemoteAdapter', CFBundlePackageType='FMWK', CFBundleVersion='1')))
shutil.copy2(vendor / 'bin/mediaremote-adapter.pl', resources)
shutil.copy2(vendor / 'LICENSE', resources / 'MediaRemoteAdapter-LICENSE.txt')
shutil.copy2(vendor / 'UPSTREAM.txt', resources / 'MediaRemoteAdapter-UPSTREAM.txt')
swift = sorted(str(p) for p in (ROOT / 'CoteDOs').rglob('*.swift'))
if not adapter_only:
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library', '-O',
        '-module-name', 'CoteDOs', '-target', 'arm64-apple-macos14.0', *swift,
        '-o', str(executable)], check=True)

app_icon = ROOT / 'CoteDOs/Assets.xcassets/AppIcon.appiconset'
with tempfile.TemporaryDirectory(prefix='dynamic-bangs-icon-') as temporary:
    iconset = Path(temporary) / 'DynamicBangs.iconset'
    iconset.mkdir()
    for side in (16, 32, 128, 256, 512):
        shutil.copy2(app_icon / f'icon_{side}.png', iconset / f'icon_{side}x{side}.png')
        shutil.copy2(app_icon / f'icon_{side * 2}.png', iconset / f'icon_{side}x{side}@2x.png')
    subprocess.run(['iconutil', '-c', 'icns', '-o', str(resources / 'DynamicBangs.icns'), str(iconset)], check=True)

info = plistlib.loads((ROOT / 'Info.plist').read_bytes())
info.pop('CFBundleIconName', None)
info['CFBundleIconFile'] = 'DynamicBangs.icns'
info['CFBundleExecutable'] = executable.name
info['CFBundleIdentifier'] = 'com.scott.notchmate'
info['CFBundleShortVersionString'] = '1.4.0-local.10'
info['CFBundleVersion'] = '10'
info['LSMinimumSystemVersion'] = '14.0'
info['NSFocusStatusUsageDescription'] = '在刘海中提示勿扰或专注模式的开启与关闭，状态仅用于本机显示。'
info['LSArchitecturePriority'] = ['arm64']
(contents / 'Info.plist').write_bytes(plistlib.dumps(info))
# String catalogs normally need Xcode. Emit equivalent .strings resources so
# this Command Line Tools build still has the upstream English translations.
catalog = json.loads((ROOT / 'CoteDOs/Localizable.xcstrings').read_text())
info_catalog = json.loads((ROOT / 'CoteDOs/InfoPlist.xcstrings').read_text())

def localized_strings(source, language):
    strings = {}
    for key, record in source['strings'].items():
        unit = record.get('localizations', {}).get(language, {}).get('stringUnit', {})
        if 'value' in unit:
            strings[key] = unit['value']
    return strings

def write_strings(path, strings):
    text = '\n'.join(json.dumps(k, ensure_ascii=False) + ' = ' + json.dumps(v, ensure_ascii=False) + ';'
                     for k, v in strings.items())
    path.write_text(text)

for language in ['en', 'de']:
    strings = localized_strings(catalog, language)
    if language == 'en':
        strings.update({'tab.music': '音乐', 'tab.timer': '番茄钟',
            'control.play': '播放', 'control.pause': '暂停', 'control.next': '下一首', 'control.previous': '上一首',
            'settings.general': '通用', 'settings.notch': '刘海', 'settings.nowPlaying': '音乐', 'settings.timer': '番茄钟',
            'settings.launchAtLogin': '登录时启动', 'settings.appearance': '外观', 'settings.data': '本机数据',
            'settings.resetData': '重置文件暂存与缓存', 'settings.resetData.done': '已重置',
            'settings.timer.name': '名称', 'settings.timer.isFocus': '记录为专注时间', 'settings.timer.isFocusHint': '将这一阶段记录为专注时间',
            'settings.timer.presets': '专注与休息安排', 'settings.timer.add': '添加计时阶段', 'timer.preset.new': '新计时',
            'settings.timer.chainHint': '列表顺序决定自动继续时的阶段顺序。勾选的阶段会记录为专注时间。',
            'settings.timer.countUp': '详情页显示已用时间', 'settings.timer.autoChain': '结束后自动进入下一阶段',
            'settings.timer.sound': '结束时播放提示音', 'settings.timer.behavior': '计时偏好',
            'settings.liveActivities': '充电、文件接收等动态提示', 'settings.audioRoute': '耳机与音频输出切换提示',
            'settings.hud': '在刘海显示音量与亮度', 'settings.suppressOSD': '用刘海替代系统音量与亮度浮层',
            'settings.notch.display': '动态提示', 'settings.audioRoute.hint': '耳机连接时 macOS 也可能显示提示，可关闭音频输出切换提示以减少重复。',
            'settings.notch.placement': '位置', 'settings.notch.resetPlacement': '重新贴合实体刘海',
            'timer.empty': '还没有计时阶段，请在详细设置中添加。'})
    folder = resources / (language + '.lproj')
    folder.mkdir(exist_ok=True)
    write_strings(folder / 'Localizable.strings', strings)
    write_strings(folder / 'InfoPlist.strings', localized_strings(info_catalog, language))
subprocess.run(['codesign', '--force', '--sign', '-', str(framework)], check=True)
subprocess.run(['codesign', '--force', '--sign', '-', str(APP)], check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(APP)], check=True)
print(APP)
