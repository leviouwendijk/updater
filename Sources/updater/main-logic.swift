// import ArgumentParser
// import Foundation
// import plate
// import Interfaces
// import Executable
// import AppKit

// public func defaultSBMBin() -> String {
//     let home = FileManager.default.homeDirectoryForCurrentUser.path
//     let path = "\(home)/sbm-bin".replacingOccurrences(of: "//", with: "/")
//     try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
//     return path
// }

// struct Updater: AsyncParsableCommand {
//     static let configuration = CommandConfiguration(
//         abstract: "Run git+swift updates across multiple repos."
//     )

//     private static let defaultConfigPath: String = {
//         guard let url = Bundle.module.url(forResource: "repos", withExtension: "json") else {
//             fatalError("Couldn’t find repos.json in bundle resources")
//         }
//         return url.path
//     }()

//     @Option(name: [.short, .long], help: "Path to your JSON config (default: bundled repos.json)")
//     var config: String = Updater.defaultConfigPath

//     func run() async throws {
//         let url = URL(fileURLWithPath: config).resolvingSymlinksInPath()
//         let data = try Data(contentsOf: url)
//         let repos = try JSONDecoder().decode([RepoEntry].self, from: data)

//         for entry in repos {
//             do {
//                 try await update(entry: entry)
//             } catch let e as Shell.Error {
//                 // concise summary
//                 fputs("Failed updating \(entry.path): \(e)\n", stderr)

//                 // full dump
//                 fputs(e.localizedDescription + "\n", stderr)
//             } catch {
//                 fputs("Failed updating \(entry.path): \(String(describing: error))\n", stderr)
//             }
//         }
//     }
// }
