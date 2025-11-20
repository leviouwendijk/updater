import Foundation
import ArgumentParser
import Interfaces
import Executable

struct Updater: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run git+swift updates across multiple repos."
    )

    // private static let defaultConfigPath: String = {
    //     guard let url = Bundle.module.url(forResource: "objects", withExtension: "json") else {
    //         fatalError("Couldn’t find repos.json in bundle resources")
    //     }
    //     return url.path
    // }()

    // @Option(name: [.short, .long], help: "Path to your JSON config (default: bundled repos.json)")
    // var config: String = Updater.defaultConfigPath

    @Option(name: [.short, .long], help: "Path to your JSON config")
    var config: String?

    @Flag(help: "Avoid resets on hard head repos (on by default to ensure updates roll out)")
    var safe: Bool = false

    func run() async throws {
        // let url = URL(fileURLWithPath: config).resolvingSymlinksInPath()
        // let data = try Data(contentsOf: url)
        // let objects = try JSONDecoder().decode([RenewableObject].self, from: data)
        let objects: [RenewableObject]

        if let configPath = config {
            let url = URL(fileURLWithPath: configPath).resolvingSymlinksInPath()
            let data = try Data(contentsOf: url)
            objects = try JSONDecoder().decode([RenewableObject].self, from: data)
        } else {
            objects = Self.embeddedObjects
        }

        try await ObjectRenewer.update(objects: objects, safe: safe)
    }
}

extension Updater {
    static let embeddedObjects: [RenewableObject] = [
        RenewableObject(
            path: "~/myworkdir/programming/scripts/updater",
            compilable: true,
            relaunch: nil,
            ignore: nil
        ),
        RenewableObject(
            path: "~/myworkdir/programming/resources",
            compilable: false,
            relaunch: nil,
            ignore: nil
        ),
        RenewableObject(
            path: "~/myworkdir/programming/scripts/numbers-parser",
            compilable: true,
            relaunch: nil,
            ignore: nil
        ),
        RenewableObject(
            path: "~/myworkdir/programming/scripts/mailer",
            compilable: true,
            relaunch: nil,
            ignore: nil
        ),
        RenewableObject(
            path: "~/myworkdir/programming/applications/Responder",
            compilable: true,
            relaunch: RelaunchConfig(enable: true, target: "infer"),
            ignore: nil
        ),
        RenewableObject(
            path: "~/myworkdir/programming/applications/Picker",
            compilable: true,
            relaunch: RelaunchConfig(enable: true, target: "infer"),
            ignore: nil
        ),
        RenewableObject(
            path: "~/myworkdir/programming/scripts/travel-quote",
            compilable: true,
            relaunch: nil,
            ignore: true
        ),
        RenewableObject(
            path: "~/myworkdir/programming/scripts/swift-build-manager",
            compilable: true,
            relaunch: nil,
            ignore: nil
        ),
        RenewableObject(
            path: "~/myworkdir/programming/applications/DiskMapper",
            compilable: true,
            relaunch: RelaunchConfig(enable: true, target: "infer"),
            ignore: nil
        )
    ]
}
