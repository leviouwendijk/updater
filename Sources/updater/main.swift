import ArgumentParser
import Foundation
import plate

enum RepoType: String, Codable {
    case script
    case application
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

func findBuiltExecutable(_ exe: String, in repo: URL) throws -> URL {
    let buildRoot = repo.appendingPathComponent(".build")
    let contents  = try FileManager.default.contentsOfDirectory(atPath: buildRoot.path)
    for sub in contents where sub != "checkouts" && sub != "manifest-cache" {
        let candidate = buildRoot
        .appendingPathComponent(sub)
        .appendingPathComponent("release")
        .appendingPathComponent(exe)
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
    }
    // fallback old layout
    let fallback = buildRoot
    .appendingPathComponent("release")
    .appendingPathComponent(exe)
    if FileManager.default.fileExists(atPath: fallback.path) {
        return fallback
    }
    throw NSError(domain: "UpdaterError",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey:
        "Couldn’t find built binary for ".ansi(.yellow) + "\(exe)".ansi(.yellow, .bold)])
}

func update(repo entry: RepoEntry) throws {
    let raw      = entry.path as NSString
    let expanded = raw.expandingTildeInPath
    let dirURL   = URL(fileURLWithPath: expanded)
    let home     = FileManager.default.homeDirectoryForCurrentUser.path

    print("\n    Updating \(expanded)…")
    try run("git",   args: ["reset","--hard","HEAD"], in: dirURL)
    try run("git",   args: ["pull","origin","master"], in: dirURL)
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

            try? FileManager.default.removeItem(atPath: destPath)
            try FileManager.default.moveItem(atPath: builtPath, toPath: destPath)
            print("    [MOVE] \(exe) → \(destPath)")

            print("    [COMPLETED MOVE] sbm-bin/ now contains ".ansi(.green) + "\(exe)".ansi(.green, .bold))

            let metaURL = URL(fileURLWithPath: binDir)
               .appendingPathComponent("\(exe).metadata")
            let meta = "ProjectRootPath=\(expanded)\n"
            try meta.write(to: metaURL, atomically: true, encoding: .utf8)
            print("    [META] Wrote metadata: \(metaURL.path)")

            continue
        }
    }
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
