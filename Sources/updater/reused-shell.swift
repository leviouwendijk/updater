// import Foundation
// import plate
// import Interfaces

// @discardableResult
// public func sh(
//     _ exec: Shell.Exec = .zsh,
//     _ program: String,
//     _ args: [String],
//     cwd: URL,
//     redactions: [String] = []
// ) async throws -> Shell.Result {
//     var opt = Shell.Options()
//     opt.cwd = cwd
//     opt.redactions = redactions
//     opt.teeToStdout = true
//     opt.teeToStderr = true

//     // Optional: per-chunk callbacks
//     // opt.onStdoutChunk = { _ in }
//     // opt.onStderrChunk = { _ in }

//     return try await Shell(exec).run("/usr/bin/env", [program] + args, options: opt)
// }
