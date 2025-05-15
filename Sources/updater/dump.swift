
// func findBuiltExecutable(_ exe: String, in repo: URL) throws -> URL {
//     let buildRoot = repo.appendingPathComponent(".build")
//     let contents  = try FileManager.default.contentsOfDirectory(atPath: buildRoot.path)
//     for sub in contents where sub != "checkouts" && sub != "manifest-cache" {
//         let candidate = buildRoot
//         .appendingPathComponent(sub)
//         .appendingPathComponent("release")
//         .appendingPathComponent(exe)
//         if FileManager.default.fileExists(atPath: candidate.path) {
//             return candidate
//         }
//     }
//     // fallback old layout
//     let fallback = buildRoot
//     .appendingPathComponent("release")
//     .appendingPathComponent(exe)
//     if FileManager.default.fileExists(atPath: fallback.path) {
//         return fallback
//     }
//     throw NSError(domain: "UpdaterError",
//         code: 1,
//         userInfo: [NSLocalizedDescriptionKey:
//         "Couldn’t find built binary for ".ansi(.yellow) + "\(exe)".ansi(.yellow, .bold)])
// }
