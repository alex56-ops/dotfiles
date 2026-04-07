import Cocoa

let script = NSString(string: "~/.launchd-scripts/wireguard-disconnect.sh").expandingTildeInPath

NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.sessionDidResignActiveNotification,
    object: nil,
    queue: .main
) { _ in
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/bash")
    task.arguments = [script]
    try? task.run()
}

RunLoop.main.run()
