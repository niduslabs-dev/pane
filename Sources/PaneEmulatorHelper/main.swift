// Pane Emulator: the background-only app inside Pane.app that becomes the emulator.
//
// Pane starts it through LaunchServices (`/usr/bin/open -g -n`) so the emulator runs in its own
// process coalition, not Pane's. Started from Pane's own process, the emulator would keep Pane's
// app record alive after Pane quits (the Dock shows "Running in Background" and Background Task
// Management records "Pane - background tasks"). See `EmulatorLauncher.launch`.
//
// Arguments: <pid-file> <log> <executable> <arguments…>
// - Points stdout and stderr at <log> (appending; Pane has already rotated and created it), or at
//   /dev/null when <log> is empty, and stdin at /dev/null.
// - Writes its PID to <pid-file> (through a temporary file and a rename, so Pane never reads half
//   a number), then `exec`s <executable>, so that PID is the emulator's.
// Exits 64 on missing arguments and 127 when the exec fails.
//
// `--repair <sdk> --bundle-id <id>`: the takeover's launch agent (`RepairAgent`). launchd runs
// it when `<sdk>/emulator` changes; it puts Pane's wrapper back after an emulator update
// (`TakeoverRepair.wrap`), prints what it did and exits: 0 when the wrapper is in place or there
// was nothing to do, 1 when it couldn't.
import Darwin
import PaneTakeover

let arguments = CommandLine.arguments
let usageExit: Int32 = 64
let execFailedExit: Int32 = 127
let ownerReadWrite: mode_t = 0o600

if arguments.dropFirst().first == RepairAgent.repairFlag {
    guard let request = RepairAgent.parse(Array(arguments.dropFirst())) else { exit(usageExit) }
    let outcome = TakeoverRepair.wrap(
        sdk: request.sdk, script: TakeoverWrapper.script(bundleID: request.bundleID),
        options: RepairAgent.agentOptions(lockFile: TakeoverRepair.defaultLockFile()))
    print("Pane Emulator: repair \(request.sdk.path(percentEncoded: false)): \(outcome)")
    switch outcome {
    case .wrapped, .updated, .alreadyWrapped, .noFolder, .busy: exit(0)
    case .installInProgress, .foreignLauncher, .failed: exit(1)
    }
}

guard arguments.count > 3 else { exit(usageExit) }
let pidFile = arguments[1]
let logPath = arguments[2]
let executable = arguments[3]

let output = logPath.isEmpty ? -1 : open(logPath, O_WRONLY | O_CREAT | O_APPEND, ownerReadWrite)
let nothing = open("/dev/null", O_RDWR)
let sink = output >= 0 ? output : nothing
dup2(nothing, STDIN_FILENO)
dup2(sink, STDOUT_FILENO)
dup2(sink, STDERR_FILENO)
if output >= 0 { close(output) }
if nothing >= 0 { close(nothing) }

let staging = pidFile + ".partial"
let pidText = "\(getpid())\n"
let pidHandle = open(staging, O_WRONLY | O_CREAT | O_TRUNC, ownerReadWrite)
if pidHandle >= 0 {
    _ = pidText.withCString { write(pidHandle, $0, strlen($0)) }
    close(pidHandle)
    rename(staging, pidFile)
}

var execArguments: [UnsafeMutablePointer<CChar>?] = arguments.dropFirst(3).map { strdup($0) } + [nil]
execv(executable, &execArguments)
let reason = String(cString: strerror(errno))
fputs("Pane Emulator: couldn't start \(executable): \(reason)\n", stderr)
exit(execFailedExit)
