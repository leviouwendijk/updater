import Foundation
import plate
import Interfaces
import AppKit

public func relaunchApplication(_ directoryURL: URL, target: String? = nil) async throws {
    let repoName    = directoryURL.lastPathComponent                 // e.g. "Responder"
    let inferredApp = repoName + ".app"

    let targetAppName = (target == "infer") ? inferredApp : (target ?? inferredApp)
    let appBundleName = targetAppName.hasSuffix(".app") ? targetAppName : targetAppName + ".app"
    let appBundleURL  = directoryURL.appendingPathComponent(appBundleName)

    let fm = FileManager.default
    guard fm.fileExists(atPath: appBundleURL.path) else {
        print("    No \(appBundleName) found at \(appBundleURL.path); skipping launch.")
        return
    }

    // Read executable + bundle id from Info.plist (authoritative)
    guard let bundle = Bundle(url: appBundleURL),
          let execName = bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String
    else {
        print("    Could not read CFBundleExecutable from \(appBundleURL.path); skipping.")
        return
    }
    let bundleID = bundle.bundleIdentifier

    // 1) Preferred: find/terminate by bundle identifier
    var terminated = false
    if let bid = bundleID {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bid)
        if !running.isEmpty {
            print("    [RUNNING] \(bid) → \(running.map { $0.processIdentifier }.map(String.init).joined(separator: ","))")
            for app in running {
                _ = app.terminate()
            }
            // Give it a moment to terminate cleanly; force if needed
            for app in running {
                if app.isTerminated == false {
                    usleep(200_000) // 200ms
                    if app.isTerminated == false {
                        _ = app.forceTerminate()
                    }
                }
            }
            terminated = true
            print("    [STOPPED] \(bid)")
        } else {
            print("    [NOT RUNNING] \(bid)")
        }
    } else {
        print("    [INFO] No bundle identifier; falling back to pgrep/killall.")
    }

    // 2) Fallback: pgrep -x <execName>, else -f <bundle path>
    if terminated == false {
        var opt = Shell.Options(); opt.cwd = directoryURL

        // exact process name
        let p1 = try? await Shell(.path("/usr/bin/pgrep"))
            .run("/usr/bin/pgrep", ["-x", execName], options: opt)
        let pidText = p1?.stdoutText().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let exactHit = (p1?.exitCode == 0) && !pidText.isEmpty

        let runningDesc = exactHit ? "\(execName) \(pidText)" : "(no exact name match)"
        print("    [CHECK pgrep -x] \(runningDesc)")

        if exactHit {
            _ = try? await Shell(.path("/usr/bin/killall"))
                .run("/usr/bin/killall", ["-TERM", execName], options: opt)
            print("    [STOPPED] \(execName)")
        } else {
            // try -f with full bundle path
            let p2 = try? await Shell(.path("/usr/bin/pgrep"))
                .run("/usr/bin/pgrep", ["-f", appBundleURL.path], options: opt)
            let pid2 = p2?.stdoutText().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if (p2?.exitCode == 0) && !pid2.isEmpty {
                print("    [CHECK pgrep -f] \(pid2)")
                // killall still wants the executable name
                _ = try? await Shell(.path("/usr/bin/killall"))
                    .run("/usr/bin/killall", ["-TERM", execName], options: opt)
                print("    [STOPPED] \(execName)")
            } else {
                print("    [NOT RUNNING] \(execName)")
            }
        }
    }

    if terminated {
        var optOpen = Shell.Options(); optOpen.cwd = directoryURL
        _ = try await Shell(.path("/usr/bin/open"))
        .run("/usr/bin/open", [appBundleURL.path], options: optOpen)

        print("    [RE-LAUNCHED] \(appBundleName)".ansi(.green))
    }
}
