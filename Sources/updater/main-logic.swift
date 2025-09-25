import ArgumentParser
import Foundation
import plate
import Interfaces
import Executable
import AppKit

enum RepoType: String, Codable {
    case script
    case application
    case resource
}

struct CompileSpec: Codable {
    let process: String
    let arguments: [String]
}

struct RelaunchSpec: Codable {
    var enable: Bool
    var target: String? 
    
    public init(
        enable: Bool = false,
        target: String? = nil
    ) {
        self.enable = enable
        self.target = target
    }
}

struct RepoEntry: Codable {
    let path: String
    let type: RepoType?          
    let compile: CompileSpec?    
    var relaunch: RelaunchSpec?
}

@discardableResult
public func sh(
    _ exec: Shell.Exec = .zsh,
    _ program: String,
    _ args: [String],
    cwd: URL
) async throws -> Shell.Result {
    var opt = Shell.Options()
    opt.cwd = cwd
    return try await Shell(exec).run("/usr/bin/env", [program] + args, options: opt)
}

public func repositoryIsOutdated(_ directoryURL: URL) async throws -> Bool {
    _ = try await sh(.zsh, "git", ["fetch","origin","--prune"], cwd: directoryURL)

    let localHead  = try await sh(.zsh, "git", ["rev-parse","HEAD"], cwd: directoryURL)
    .stdoutText().trimmingCharacters(in: .whitespacesAndNewlines)
    let remoteHead = try await sh(.zsh, "git", ["rev-parse","@{u}"], cwd: directoryURL)
    .stdoutText().trimmingCharacters(in: .whitespacesAndNewlines)

    return localHead != remoteHead
}

// private func fallbackBuildAndDeploy(
//     in dirURL: URL,
//     repoType: RepoType?
// ) async throws {
//     // Update deps and build
//     _ = try await sh(.zsh, "swift", ["package","update"], cwd: dirURL)
//     let config = Executable.Build.Config(mode: .release)
//     _ = try await Executable.Build.build(at: dirURL, config: config)
//     print("    [SUCCESS] build completed".ansi(.green))

//     // Find executable targets
//     let executables = (try? await Executable.Targets.executableNames(in: dirURL)) ?? []
//     guard !executables.isEmpty else {
//         print("    No executable targets found.".ansi(.yellow))
//         return
//     }

//     // application type = keep local (no deploy), else deploy to ~/sbm-bin
//     if repoType == .application {
//         if let exe = executables.first {
//             print("    [COMPLETED LOCAL] Repository now contains: ".ansi(.green) + exe.ansi(.green, .bold))
//         }
//         return
//     }

//     let binDir = defaultSBMBin()
//     let dest = URL(fileURLWithPath: binDir)
//     try Executable.Deploy.selected(
//         from: dirURL,
//         config: config,
//         to: dest,
//         targets: executables,
//         perTargetDestinations: [:]
//     )
// }

private func defaultSBMBin() -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let path = "\(home)/sbm-bin".replacingOccurrences(of: "//", with: "/")
    try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    return path
}

// MARK: - Relaunch for applications


private func relaunchApplication(_ directoryURL: URL, target: String? = nil) async throws {
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


private func runCompileSpec(_ spec: CompileSpec, in dirURL: URL) async throws {
    // Use Interfaces.Shell so we get streaming, timeouts, redactions if needed.
    var opt = Shell.Options(); opt.cwd = dirURL
    let args = spec.arguments
    let res = try await Shell(.zsh).run("/usr/bin/env", [spec.process] + args, options: opt)
    if let code = res.exitCode, code != 0 {
        throw ValidationError("Compile process \(spec.process) exited with \(code)")
    }
}

private func update(entry: RepoEntry) async throws {
    let expanded = (entry.path as NSString).expandingTildeInPath
    let dirURL   = URL(fileURLWithPath: expanded)

    print("\n    Checking \(expanded)…")
    guard (try? await repositoryIsOutdated(dirURL)) == true else {
        print("    No upstream changes; skipping.".ansi(.bold))
        return
    }

    print("    Updating…")
    _ = try await sh(.zsh, "git", ["reset","--hard","HEAD"], cwd: dirURL)
    _ = try await sh(.zsh, "git", ["pull","origin","master"], cwd: dirURL)

    if let compile = entry.compile {
        try await runCompileSpec(compile, in: dirURL)
    }
    // } else {
    //     try await fallbackBuildAndDeploy(in: dirURL, repoType: entry.type ?? .resource)
    // }

    // if entry.type == .application {
    if let relaunch = entry.relaunch?.enable {
        if relaunch {
            try await relaunchApplication(dirURL, target: entry.relaunch?.target)
        }
    }

    print("")
}

struct Updater: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run git+swift updates across multiple repos."
    )

    private static let defaultConfigPath: String = {
        guard let url = Bundle.module.url(forResource: "repos", withExtension: "json") else {
            fatalError("Couldn’t find repos.json in bundle resources")
        }
        return url.path
    }()

    @Option(name: [.short, .long], help: "Path to your JSON config (default: bundled repos.json)")
    var config: String = Updater.defaultConfigPath

    func run() async throws {
        let url = URL(fileURLWithPath: config).resolvingSymlinksInPath()
        let data = try Data(contentsOf: url)
        let repos = try JSONDecoder().decode([RepoEntry].self, from: data)

        for entry in repos {
            do {
                try await update(entry: entry)
            } catch let e as Shell.Error {
                // concise summary
                fputs("Failed updating \(entry.path): \(e)\n", stderr)

                // full dump
                fputs(e.pretty() + "\n", stderr)
            } catch {
                fputs("Failed updating \(entry.path): \(String(describing: error))\n", stderr)
            }
        }
    }
}
