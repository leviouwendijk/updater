import ArgumentParser
import Foundation
import plate

enum RepoType: String, Codable {
    case script
    case application
    case resource
}

func isSwiftExecutable(repoType: RepoType) -> Bool {
    switch repoType {
        case .script:
        return true
        case .application:
        return true
        case .resource:
        return false
    }
}

struct RepoEntry: Codable {
    let path: String
    let type: RepoType?
}

struct PackageDump: Decodable {
    struct Target: Decodable {
        let name: String
        let type: String
    }
    let targets: [Target]
}

@discardableResult
func run(_ cmd: String, args: [String], in cwd: URL) throws -> String {
    let task = Process()
    task.environment = ProcessInfo.processInfo.environment

    task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    task.arguments = [cmd] + args
    task.currentDirectoryURL = cwd

    task.standardInput = FileHandle(forReadingAtPath: "/dev/null")

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError  = pipe

    try task.run()
    task.waitUntilExit()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let out  = String(decoding: data, as: UTF8.self).ansi(.brightBlack)

    if task.terminationStatus != 0 {
        throw NSError(
            domain: "UpdaterError",
            code: Int(task.terminationStatus),
            userInfo: [NSLocalizedDescriptionKey: out]
        )
    }

    print(out.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines))
    return out
}

func dumpPackageJSON(in repo: URL) throws -> Data {
    let task = Process()
    task.executableURL       = URL(fileURLWithPath: "/usr/bin/env")
    task.arguments           = ["swift", "package", "dump-package"]
    task.currentDirectoryURL = repo

    let pipe = Pipe()
    task.standardOutput = pipe
    try task.run()
    task.waitUntilExit()

    guard task.terminationStatus == 0 else {
        throw NSError(
          domain: "UpdaterError",
          code: Int(task.terminationStatus),
          userInfo: nil
        )
    }

    return pipe.fileHandleForReading.readDataToEndOfFile()
}

func findExecutableTargets(in repo: URL) throws -> [String] {
    let data = try dumpPackageJSON(in: repo)
    let dump = try JSONDecoder().decode(PackageDump.self, from: data)
    return dump.targets
       .filter { $0.type == "executable" }
       .map { $0.name }
}

func repositoryIsOutdated(_ directoryURL: URL) throws -> Bool {
    _ = try run("git", args: ["fetch", "origin", "--prune"], in: directoryURL)

    let localHead  = try run("git", args: ["rev-parse", "HEAD"], in: directoryURL)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
    let remoteHead = try run("git",
                        args: ["rev-parse", "@{u}"],
                        in: directoryURL)
                        .trimmingCharacters(in: .whitespacesAndNewlines)

    return localHead != remoteHead
}

func relaunchApplication(_ directoryURL: URL) throws {
    let repoName     = directoryURL.lastPathComponent
    let appBundleURL = directoryURL.appendingPathComponent("\(repoName).app")

    guard FileManager.default.fileExists(atPath: appBundleURL.path) else {
        print("    No \(repoName).app found at \(appBundleURL.path); skipping launch.")
        return
    }

    let pgrep = Process()
    pgrep.executableURL       = URL(fileURLWithPath: "/usr/bin/pgrep")
    pgrep.arguments           = ["-x", repoName]
    pgrep.currentDirectoryURL = directoryURL

    let pidPipe = Pipe()
    pgrep.standardOutput = pidPipe

    try pgrep.run(); pgrep.waitUntilExit()
    let pidData   = pidPipe.fileHandleForReading.readDataToEndOfFile()
    let pidString = String(decoding: pidData, as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)

    let isRunning = (pgrep.terminationStatus == 0) && !pidString.isEmpty

    if isRunning {
        print("    [RUNNING] \(repoName)".ansi(.yellow))
        print("    [PROCESS ID] \(pidString)".ansi(.brightBlack))
        let killall = Process()
        killall.executableURL       = URL(fileURLWithPath: "/usr/bin/killall")
        killall.arguments           = ["-TERM", repoName]
        killall.currentDirectoryURL = directoryURL
        try killall.run(); killall.waitUntilExit()
        print("    [STOPPED] \(repoName)")

        let opener = Process()
        opener.executableURL       = URL(fileURLWithPath: "/usr/bin/open")
        opener.arguments           = [appBundleURL.path]
        opener.currentDirectoryURL = directoryURL
        try opener.run()
        print("    [RE-LAUNCHED] \(repoName).app".ansi(.green))
    } else {
        print("    [NOT RUNNING] \(repoName)")
    }
}

func update(repo entry: RepoEntry) throws {
    let raw      = entry.path as NSString
    let expanded = raw.expandingTildeInPath
    let dirURL   = URL(fileURLWithPath: expanded)
    let home     = FileManager.default.homeDirectoryForCurrentUser.path

    if try !repositoryIsOutdated(dirURL) {
        print("    No upstream changes; skipping.".ansi(.bold))
        return
    }

    print("\n    Updating \(expanded)…")
    try run("git",   args: ["reset","--hard","HEAD"], in: dirURL)
    try run("git",   args: ["pull","origin","master"], in: dirURL)

    if isSwiftExecutable(repoType: entry.type ?? .resource) {
        try run("swift", args: ["package","update"],       in: dirURL)

        try run("swift", args: ["build", "-c", "release"], in: dirURL)
        print("    [SUCCESS] build completed".ansi(.green))

        let executables = try findExecutableTargets(in: dirURL)
        guard !executables.isEmpty else {
            print("No executable targets found.".ansi(.yellow))
            return
        }

        let binDir = "\(home)/sbm-bin"
            .replacingOccurrences(of: "//", with: "/")

        try FileManager.default
            .createDirectory(atPath: binDir, withIntermediateDirectories: true)

        for exe in executables {
            let local = (entry.type == .application)

            if local {
                print("    [COMPLETED LOCAL] Repository now contains: ".ansi(.green) + "\(exe)".ansi(.green, .bold))
            } else {
                print("    Moving: \(exe) → \(binDir)/\(exe)…")

                let builtPath = dirURL
                   .appendingPathComponent(".build")
                   .appendingPathComponent("release")
                   .appendingPathComponent(exe)
                   .path
                let destPath = "\(binDir)/\(exe)"

                if !FileManager.default.fileExists(atPath: builtPath) {
                    print("    [ERROR] Binary not found in build directory ".ansi(.red) + "\(exe)".ansi(.red, .bold))
                    print("    Inspect path: \(builtPath)".ansi(.red))
                    continue
                }

                try? FileManager.default.removeItem(atPath: destPath)
                try FileManager.default.moveItem(atPath: builtPath, toPath: destPath)
                print("    [MOVE] \(exe) → \(destPath)")

                print("    [COMPLETED MOVE] sbm-bin/ now contains ".ansi(.green) + "\(exe)".ansi(.green, .bold))

                let metaURL = URL(fileURLWithPath: binDir)
                   .appendingPathComponent("\(exe).metadata")
                let meta = "ProjectRootPath=\(expanded)\n"
                try meta.write(to: metaURL, atomically: true, encoding: .utf8)
                print("    [META] Wrote metadata: \(metaURL.path)")
            }
        }

        if entry.type == .application {
            try relaunchApplication(dirURL)
        }
    }

    print("")
}

struct Updater: ParsableCommand {
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

    func run() throws {
        let url = URL(fileURLWithPath: config).resolvingSymlinksInPath()
        let data = try Data(contentsOf: url)
        let repos = try JSONDecoder().decode([RepoEntry].self, from: data)

        for entry in repos {
            do {
                try update(repo: entry)
            } catch {
                fputs("Failed updating \(entry.path): \(error.localizedDescription)\n".ansi(.red), stderr)
            }
        }
    }
}

Updater.main()
