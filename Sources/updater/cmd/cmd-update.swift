import Foundation
import ArgumentParser
import Interfaces
import Executable

struct Updater: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run git+swift updates across multiple repos."
    )

    private static let defaultConfigPath: String = {
        guard let url = Bundle.module.url(forResource: "objects", withExtension: "json") else {
            fatalError("Couldn’t find repos.json in bundle resources")
        }
        return url.path
    }()

    @Option(name: [.short, .long], help: "Path to your JSON config (default: bundled repos.json)")
    var config: String = Updater.defaultConfigPath

    @Flag(help: "Avoid resets on hard head repos (on by default to ensure updates roll out)")
    var safe: Bool = false

    func run() async throws {
        let url = URL(fileURLWithPath: config).resolvingSymlinksInPath()
        let data = try Data(contentsOf: url)
        // let repos = try JSONDecoder().decode([RepoEntry].self, from: data)
        let objects = try JSONDecoder().decode([RenewableObject].self, from: data)

        try await ObjectRenewer.update(objects: objects, safe: safe)
        // for entry in repos {
        //     do {
        //         try await update(entry: entry, safe: safe)
        //     } catch let e as Shell.Error {
        //         // concise summary
        //         fputs("Failed updating \(entry.path): \(e)\n", stderr)

        //         // full dump
        //         fputs(e.localizedDescription + "\n", stderr)
        //     } catch {
        //         fputs("Failed updating \(entry.path): \(String(describing: error))\n", stderr)
        //     }
        // }
    }
}
