import AppKit

let application = NSApplication.shared
let controller = AppController.shared
let arguments = CommandLine.arguments

if arguments.contains("--shortcuts") {
    controller.shortcutDiagnostics()
} else if arguments.contains("--diagnostics") {
    controller.diagnostics()
} else if let index = arguments.firstIndex(of: "--icon"), arguments.indices.contains(index + 1) {
    do { try writeAppIcon(to: arguments[index + 1]) }
    catch { FileHandle.standardError.write(Data("\(error)\n".utf8)); exit(1) }
} else if let index = arguments.firstIndex(of: "--render"), arguments.indices.contains(index + 1) {
    do { try controller.renderPreview(to: arguments[index + 1]); print("Rendered both pages in light and dark appearance.") }
    catch { FileHandle.standardError.write(Data("\(error)\n".utf8)); exit(1) }
} else {
    application.delegate = controller
    application.run()
}
