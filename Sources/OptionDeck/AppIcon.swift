import AppKit
import SwiftUI

@MainActor
func writeAppIcon(to path: String) throws {
    let directory = URL(fileURLWithPath: path, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for size in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let content = ZStack {
                RoundedRectangle(cornerRadius: 115, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.3, green: 0.55, blue: 0.96), Color(red: 0.12, green: 0.31, blue: 0.75)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .padding(12)
                    .shadow(color: .black.opacity(0.2), radius: 5, y: 4)
                RoundedRectangle(cornerRadius: 112, style: .continuous)
                    .strokeBorder(.white.opacity(0.25), lineWidth: 2).padding(14)
                Image(systemName: "option").font(.system(size: 270, weight: .medium)).foregroundStyle(.white)
            }.frame(width: 512, height: 512)
            let renderer = ImageRenderer(content: content)
            renderer.scale = Double(size * scale) / 512
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else {
                throw ScriptFailure.failed("앱 아이콘 생성 실패")
            }
            try png.write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"))
        }
    }
}
