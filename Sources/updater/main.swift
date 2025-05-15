import ArgumentParser
import Foundation

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
    let out  = String(decoding: data, as: UTF8.self)

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

func update(repo entry: RepoEntry) throws {
    let raw      = entry.path as NSString
    let expanded = raw.expandingTildeInPath
    let dirURL   = URL(fileURLWithPath: expanded)
    let home     = FileManager.default.homeDirectoryForCurrentUser.path

    print("\n    Updating \(expanded)…")
    try run("git",   args: ["reset","--hard","HEAD"], in: dirURL)
    try run("git",   args: ["pull","origin","master"], in: dirURL)
    try run("swift", args: ["package","update"],       in: dirURL)

    let executables = try findExecutableTargets(in: dirURL)
    guard !executables.isEmpty else {
        print("No executable targets found.")
        return
    }

    let binDir = "\(home)/sbm-bin"
    try FileManager.default
        .createDirectory(atPath: binDir, withIntermediateDirectories: true)

    for exe in executables {
        if entry.type == .application {
            print("    Building locally: \(exe)…")
            try run("swift",
                    args: ["build","-c","release","--target",exe],
                    in: dirURL)
        } else {
            let outPath = "\(binDir)/\(exe)"
            print("    Building & deploying: \(exe) → \(outPath)…")
            try run("swift", args: [
                "build","-c","release",
                "--target",exe,
                "-Xswiftc","-o",
                "-Xswiftc",outPath
            ], in: dirURL)

            let meta = "ProjectRootPath=\(expanded)\n"
            let metaURL = URL(fileURLWithPath: binDir).appendingPathComponent("\(exe).metadata")

            try meta.write(to: metaURL, atomically: true, encoding: .utf8)
            print("    Wrote metadata: \(metaURL.path)")
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
                fputs("Failed updating \(entry.path): \(error.localizedDescription)\n", stderr)
            }
        }
    }
}

Updater.main()
