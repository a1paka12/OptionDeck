#!/usr/bin/env python3
"""Capture the real SwiftUI views offscreen; never activate the app or send input.

Requires a release build (scripts/build.sh). Only temporary copies receive replay
hooks; production sources, preferences, brightness, volume and media are untouched.
"""
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / '.build/native-ui'
WORK.mkdir(parents=True, exist_ok=True)
BUILD = Path(subprocess.check_output(['swift', 'build', '-c', 'release', '--show-bin-path'], cwd=ROOT, text=True).strip())
for source in (ROOT / 'Sources/OptionDeck').glob('*.swift'):
    if source.name in ('main.swift', 'AppController.swift'):
        continue
    text = source.read_text()
    if source.name == 'DeckSettings.swift':
        old = 'static func load() throws -> SettingsDocument { try request(.init(op: "load")) }'
        assert old in text
        text = text.replace(old, 'static func load() throws -> SettingsDocument { .init(schema: 1, revision: 0, settings: .init()) }')
        old = 'try request(.init(op: "save", expected_revision: revision, settings: settings))'
        assert old in text
        text = text.replace(old, '.init(schema: 1, revision: revision + 1, settings: settings)')
    if source.name == 'DeckSettingsView.swift':
        old = '.onChange(of: model.settingsTab)'
        assert old in text
        text = text.replace(old, '.onReceive(NotificationCenter.default.publisher(for: Notification.Name("NativeFilmReplay"))) { replay($0) }\n            ' + old, 1)
        insertion = '''
    // Capture-only driver: uses this view's actual editor functions and state.
    private func replay(_ note: Notification) {
        guard let command = note.userInfo?["command"] as? String else { return }
        let token = note.userInfo?["token"] as? String ?? "media:1"
        let target = note.userInfo?["target"] as? String ?? "media:0"
        switch command {
        case "ghost":
            if dragSource == nil { dragBase = pageTiles; dragFrames = slotFrames }
            dragSource = "library:3"
            let x = note.userInfo?["x"] as? Double ?? 340
            let y = note.userInfo?["y"] as? Double ?? 190
            dragLocation = CGPoint(x: x, y: y)
            dropTarget = target
            updatePreview(source: "library:3", target: target)
        case "drop":
            _ = drop("library:3", onto: target)
            dragSource = nil; dragLocation = nil; dropTarget = nil
            previewPacking = nil; previewTarget = nil; ghostTile = nil; dragBase = []; dragFrames = [:]
        case "resize":
            resizeTile(token, columns: note.userInfo?["columns"] as? Int ?? 3, rows: note.userInfo?["rows"] as? Int ?? 1)
        case "outside":
            if dragSource == nil { dragBase = pageTiles; dragFrames = slotFrames }
            dragSource = token; dropTarget = nil; previewPacking = nil
            dragLocation = CGPoint(x: note.userInfo?["x"] as? Double ?? 100, y: note.userInfo?["y"] as? Double ?? 190)
        case "remove":
            removeTile(token)
            dragSource = nil; dragLocation = nil; dropTarget = nil; dragBase = []; dragFrames = [:]
        case "apply":
            model.settings = draft
            model.geometry = try? DeckGeometry(settings: draft)
        default: break
        }
    }
'''
        marker = '    private func destination(at location:'
        assert marker in text
        text = text.replace(marker, insertion + '\n' + marker, 1)
    (WORK / source.name).write_text(text)

command = ['swiftc', '-parse-as-library', '-swift-version', '6', '-O', '-I', str(BUILD / 'Modules')]
for name in ('SystemBridge', 'DeckEngineBridge'):
    command += ['-I', str(BUILD / f'{name}.build'), '-Xcc', '-I' + str(ROOT / 'Sources' / name / 'include')]
command += [str(p) for p in WORK.glob('*.swift') if p.name != 'Capture.swift']
command += [str(ROOT / 'scripts/motion/capture_native.swift')]
for name in ('DeckCore', 'SystemBridge', 'DeckEngineBridge'):
    command += [str(p) for p in (BUILD / f'{name}.build').glob('*.o')]
command += ['-L', str(ROOT / 'engine/target/release'), '-ldeck_engine', '-liconv']
for framework in ('AppKit', 'SwiftUI', 'CoreAudio', 'ApplicationServices', 'AVFoundation'):
    command += ['-framework', framework]
command += ['-o', str(WORK / 'capture-native')]
subprocess.run(command, check=True, cwd=ROOT)
subprocess.run([str(WORK / 'capture-native'), str(WORK)], check=True, cwd=ROOT)
