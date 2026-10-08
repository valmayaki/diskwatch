// Diskwatch.app launcher (macOS 12+).
//
//   diskwatch-launcher <args...>      run the bundled diskwatch script as a CHILD and wait.
//                                      macOS privacy (TCC) attributes a child's file access
//                                      to the app that spawned it; never exec() bash here.
//   diskwatch-launcher --register      enable the background agent (com.diskwatch.agent)
//   diskwatch-launcher --unregister    disable it
//   diskwatch-launcher --agent-status  print: enabled | requires-approval | not-registered
//
// The agent is one fixed job that runs `diskwatch tick` every 5 minutes; the user's
// schedule lives outside the bundle (diskwatch schedule), so the signed app never changes.
// macOS 13+: registered from inside the bundle with SMAppService (shown in Login Items).
// macOS 12:  written to ~/Library/LaunchAgents and loaded with launchctl.
import Foundation
import ServiceManagement

let agentLabel = "com.diskwatch.agent"
let agentPlistName = "\(agentLabel).plist"
let fm = FileManager.default

let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
let bundleURL: URL = {
    // Prefer Bundle.main; fall back to <app>/Contents/MacOS/<exe> -> <app>.
    let b = Bundle.main.bundleURL
    if b.pathExtension == "app" { return b }
    return exe.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
}()
let contents = bundleURL.appendingPathComponent("Contents")
let launcherPath = contents.appendingPathComponent("MacOS/diskwatch-launcher").path
let legacyPlist = fm.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/LaunchAgents/\(agentPlistName)")

func eprint(_ s: String) { FileHandle.standardError.write((s + "\n").data(using: .utf8)!) }

@discardableResult
func run(_ path: String, _ args: [String], quiet: Bool = true) -> Int32 {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    if quiet { p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice }
    do { try p.run() } catch { return -1 }
    p.waitUntilExit()
    return p.terminationStatus
}

func capture(_ path: String, _ args: [String]) -> String {
    let p = Process(); let pipe = Pipe()
    p.executableURL = URL(fileURLWithPath: path); p.arguments = args
    p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return "" }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(decoding: data, as: UTF8.self)
}

// Wait for the agent's first run after registration: true once it runs or exits 0,
// false if launchd rejects it (EX_CONFIG 78 / OS_REASON_CODESIGNING).
func firstRunOK(timeout: Int = 15) -> Bool {
    for _ in 0..<timeout {
        sleep(1)
        let st = capture("/bin/launchctl", ["print", "\(uidDomain)/\(agentLabel)"])
        if st.contains("state = running") || st.contains("last exit code = 0") { return true }
        if st.contains("last exit code = 78") || st.contains("OS_REASON_CODESIGNING") { return false }
    }
    return false
}

// ---- macOS 12 fallback: plain LaunchAgent file (same job, absolute program path)

func legacyPlistData() throws -> Data {
    let plist: [String: Any] = [
        "Label": agentLabel,
        "ProgramArguments": [launcherPath, "tick"],
        "StartInterval": 300,
        "RunAtLoad": true,
        "ProcessType": "Background",
        "LowPriorityIO": true,
        "Nice": 19,
        "EnvironmentVariables": ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"],
    ]
    return try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
}

let uidDomain = "gui/\(getuid())"
// Test hook: DISKWATCH_FORCE_LEGACY=1 exercises the macOS 12 code path on newer systems.
let forceLegacy = ProcessInfo.processInfo.environment["DISKWATCH_FORCE_LEGACY"] == "1"

func legacyRegister() -> Int32 {
    do {
        try fm.createDirectory(at: legacyPlist.deletingLastPathComponent(), withIntermediateDirectories: true)
        try legacyPlistData().write(to: legacyPlist)
    } catch { eprint("Diskwatch: cannot write \(legacyPlist.path): \(error)"); return 1 }
    run("/bin/launchctl", ["bootout", "\(uidDomain)/\(agentLabel)"])
    let rc = run("/bin/launchctl", ["bootstrap", uidDomain, legacyPlist.path])
    print(rc == 0 ? "enabled (LaunchAgent \(legacyPlist.path))" : "launchctl bootstrap failed (\(rc))")
    return rc == 0 ? 0 : 1
}

func legacyUnregister() -> Int32 {
    run("/bin/launchctl", ["bootout", "\(uidDomain)/\(agentLabel)"])
    try? fm.removeItem(at: legacyPlist)
    print("not-registered")
    return 0
}

func legacyStatus() -> String {
    run("/bin/launchctl", ["print", "\(uidDomain)/\(agentLabel)"]) == 0 ? "enabled" : "not-registered"
}

// ---- macOS 13+: SMAppService agent bundled at Contents/Library/LaunchAgents

@available(macOS 13.0, *)
func smStatusText(_ s: SMAppService.Status) -> String {
    switch s {
    case .enabled: return "enabled"
    case .requiresApproval: return "requires-approval"
    case .notRegistered: return "not-registered"
    case .notFound: return "not-found"
    @unknown default: return "unknown"
    }
}

@available(macOS 13.0, *)
func smRegister() -> Int32 {
    // Drop a macOS-12-style copy if one exists, so the job is not loaded twice.
    if fm.fileExists(atPath: legacyPlist.path) { _ = legacyUnregister() }
    let svc = SMAppService.agent(plistName: agentPlistName)
    do { try svc.register() } catch {
        eprint("Diskwatch: SMAppService register failed: \(error.localizedDescription)")
    }
    if svc.status == .requiresApproval {
        print("requires-approval")
        eprint("Approve Diskwatch in System Settings → General → Login Items (opening it now).")
        SMAppService.openSystemSettingsLoginItems()
        return 0
    }
    // Background Task Management can keep a stale launch constraint for a rebuilt,
    // locally signed app, and launchd then refuses to start the bundled agent. Verify the
    // first run; fall back to the LaunchAgent file (same job, no constraint) if rejected.
    if svc.status == .enabled && firstRunOK() {
        print("enabled")
        return 0
    }
    eprint("Diskwatch: launchd rejected the bundled agent; using a LaunchAgent file instead.")
    do { try svc.unregister() } catch {}
    sleep(2)
    return legacyRegister()
}

@available(macOS 13.0, *)
func smUnregister() -> Int32 {
    let svc = SMAppService.agent(plistName: agentPlistName)
    do { try svc.unregister() } catch { /* already unregistered */ }
    if fm.fileExists(atPath: legacyPlist.path) { _ = legacyUnregister() } else { print("not-registered") }
    return 0
}

// ---- main

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "--register":
    if #available(macOS 13.0, *), !forceLegacy { exit(smRegister()) } else { exit(legacyRegister()) }
case "--unregister":
    if #available(macOS 13.0, *), !forceLegacy { exit(smUnregister()) } else { exit(legacyUnregister()) }
case "--agent-status":
    // Report the mechanism actually in use: the LaunchAgent file wins when present
    // (it is the fallback when launchd rejects the bundled agent).
    if fm.fileExists(atPath: legacyPlist.path) {
        print(legacyStatus())
    } else if #available(macOS 13.0, *), !forceLegacy {
        print(smStatusText(SMAppService.agent(plistName: agentPlistName).status))
    } else {
        print(legacyStatus())
    }
    exit(0)
default:
    break
}

// Run the bundled script as a child process.
//
// posix_spawn, not Foundation's Process: Process puts the child in a new process group,
// so it is not the terminal's foreground job and gets suspended (SIGTTOU/SIGTTIN) the
// moment an interactive command like `diskwatch ui` touches the terminal. Spawning in our
// own process group keeps Ctrl-C, job control and ncurses working; we ignore the
// terminal's interrupt signals ourselves so the child decides how to handle them.
let script = contents.appendingPathComponent("Resources/diskwatch").path
let bin = contents.appendingPathComponent("Resources/bin").path
var env = ProcessInfo.processInfo.environment
let oldPath = env["PATH"].map { $0.isEmpty ? "" : $0 + ":" } ?? ""
env["PATH"] = "\(bin):\(oldPath)/usr/bin:/bin:/usr/sbin:/sbin"
env["DISKWATCH_APP"] = bundleURL.path

let argv: [String] = ["/bin/bash", script] + args
var cArgs: [UnsafeMutablePointer<CChar>?] = argv.map { strdup($0) } + [nil]
var cEnv: [UnsafeMutablePointer<CChar>?] = env.map { strdup("\($0.key)=\($0.value)") } + [nil]

signal(SIGINT, SIG_IGN); signal(SIGQUIT, SIG_IGN)   // same group: the child receives them
var pid: pid_t = 0
let rc = posix_spawn(&pid, "/bin/bash", nil, nil, &cArgs, &cEnv)
guard rc == 0 else {
    eprint("Diskwatch: cannot start \(script): \(String(cString: strerror(rc)))")
    exit(1)
}
// Forward termination requests (launchd stop, kill) to the child.
for sig in [SIGTERM, SIGHUP] {
    signal(sig, SIG_IGN)
    let src = DispatchSource.makeSignalSource(signal: sig, queue: .global())
    src.setEventHandler { kill(pid, sig) }
    src.resume()
    _ = Unmanaged.passRetained(src)   // keep alive for the process lifetime
}
var status: Int32 = 0
while waitpid(pid, &status, 0) < 0 && errno == EINTR {}
let termSig = status & 0x7f
exit(termSig == 0 ? (status >> 8) & 0xff : 128 + termSig)
