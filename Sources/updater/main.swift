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

    @Flag(name: .shortAndLong, help: "Also pass `-l` to `sbm` for any application entries.")
    var keepLocal: Bool = false

    @Option(name: [.short, .long], help: "Path to your JSON config (default: bundled repos.json)")
    var config: String = Updater.defaultConfigPath

    func run() throws {
        let url = URL(fileURLWithPath: config).resolvingSymlinksInPath()
        let data = try Data(contentsOf: url)
        let repos = try JSONDecoder().decode([RepoEntry].self, from: data)

        for entry in repos {
            do {
                try update(repo: entry, keepLocal: keepLocal)
            } catch {
                fputs("Failed updating \(entry.path): \(error.localizedDescription)\n", stderr)
            }
        }
    }
}

// func executeSBM(_ local: Bool = false) throws {
//     do {
//         let home = FileManager.default.homeDirectoryForCurrentUser.path()
//         let process = Process()
//         process.executableURL = URL(fileURLWithPath: "/bin/zsh")

//         let base = "source ~/.zprofile && \(home)/sbm-bin/sbm -r"
//         let cmd = local ? base + " -l" : base

//         process.arguments = ["-c", cmd]
        
//         let outputPipe = Pipe()
//         let errorPipe = Pipe()
//         process.standardOutput = outputPipe
//         process.standardError = errorPipe

//         try process.run()
//         process.waitUntilExit()

//         let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
//         let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
//         let outputString = String(data: outputData, encoding: .utf8) ?? ""
//         let errorString = String(data: errorData, encoding: .utf8) ?? ""

//         if process.terminationStatus == 0 {
//             print("sbm executed successfully:\n\(outputString)")
//         } else {
//             print("Error running sbm:\n\(errorString)")
//             throw NSError(domain: "sbm", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: errorString])
//         }
//     } catch {
//         print("Error running commands: \(error)")
//         throw error
//     }
// }

func update(repo: RepoEntry, keepLocal: Bool) throws {
    let raw = repo.path as NSString
    let expanded = raw.expandingTildeInPath
    let dirURL = URL(fileURLWithPath: expanded)

    print("\n    Updating \(expanded)…")

    try run("git", args: ["reset", "--hard", "HEAD"], in: dirURL)
    try run("git", args: ["pull", "origin", "master"], in: dirURL)
    try run("swift", args: ["package", "update"], in: dirURL)

    let base = "sbm"
    var cmdArgs = ["-r"]
    if repo.type == .application || keepLocal {
        cmdArgs.append(" -l")
    }

    try run(base, args: cmdArgs, in: dirURL)
}

@discardableResult
func run(_ cmd: String, args: [String], in cwd: URL) throws -> String {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    task.arguments = [cmd] + args
    task.currentDirectoryURL = cwd

    task.environment = ProcessInfo.processInfo.environment

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

Updater.main()
