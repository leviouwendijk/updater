import ArgumentParser
import Foundation
import plate
import Interfaces
import Executable

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
    let repoName     = directoryURL.lastPathComponent
    let inferredApp  = repoName + ".app"

    func isInferredSetting() -> Bool {
        return target == "infer"
    }

    let targetApp = isInferredSetting() ? inferredApp : (target ?? inferredApp)

    let appBundleURL = directoryURL.appendingPathComponent("\(targetApp)")

    let fm = FileManager.default
    guard fm.fileExists(atPath: appBundleURL.path) else {
        print("    No \(targetApp) found at \(appBundleURL.path); skipping launch.")
        return
    }

    // pgrep
    var opt = Shell.Options(); opt.cwd = directoryURL
    let p = try await Shell(.path("/usr/bin/pgrep")).run("/usr/bin/pgrep", ["-x", targetApp], options: opt)
    let pidString = p.stdoutText().trimmingCharacters(in: .whitespacesAndNewlines)
    let isRunning = (p.exitCode == 0) && !pidString.isEmpty

    if isRunning {
        // print("    [RUNNING] \(repoName)".ansi(.yellow))
        // print("    [PROCESS ID] \(pidString)".ansi(.brightBlack))
        // _ = try await sh(.path("/usr/bin/killall"), "/usr/bin/killall", ["-TERM", repoName], cwd: directoryURL)
        // print("    [STOPPED] \(repoName)")

        // checking if it works with .app
        print("    [RUNNING] \(targetApp)".ansi(.yellow))
        print("    [PROCESS ID] \(pidString)".ansi(.brightBlack))
        _ = try await sh(.path("/usr/bin/killall"), "/usr/bin/killall", ["-TERM", targetApp], cwd: directoryURL)
        print("    [STOPPED] \(targetApp)")
        
        _ = try await sh(.path("/usr/bin/open"), "/usr/bin/open", [appBundleURL.path], cwd: directoryURL)
        print("    [RE-LAUNCHED] \(targetApp)".ansi(.green))
    } else {
        print("    [NOT RUNNING] \(targetApp)")
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
