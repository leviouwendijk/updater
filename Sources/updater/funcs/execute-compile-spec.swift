import Foundation
import Interfaces
import plate
import ArgumentParser

public func executeCompileSpec(_ spec: CompileSpec, in dirURL: URL) async throws {
    let cmdLine = (["/usr/bin/env", spec.process] + spec.arguments).map {
        $0.isEmpty ? "''" : "'" + $0.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }.joined(separator: " ")

    print("    → \(cmdLine)")

    let res = try await sh(.zsh, spec.process, spec.arguments, cwd: dirURL)

    if let code = res.exitCode, code != 0 {
        throw ArgumentParser.ValidationError("Compile process \(spec.process) exited with \(code)")
    }

    let ok = "Compile: " + "Ok".ansi(.green, .bold) + " " + res.shortSummary
    let div = String(repeating: "-", count: (50-16))
    printi(div)
    printi(ok)
    printi(div)
}
