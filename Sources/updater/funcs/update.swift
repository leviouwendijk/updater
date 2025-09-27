import Foundation
import Interfaces
import plate
import Executable

public func update(entry: RepoEntry, safe: Bool) async throws {
    let expanded = (entry.path as NSString).expandingTildeInPath
    let dirURL   = URL(fileURLWithPath: expanded)

    print("\n    Checking \(expanded)…")

    // guard (try? await GitRepo.outdated(dirURL)) == true else {
    //     print("    No upstream changes; skipping.".ansi(.bold))
    //     // return // disable return!!
    // }

    let isOutdated = (try? await GitRepo.outdated(dirURL)) == true
    if !isOutdated {
        print("    No upstream changes; continuing to version check.".ansi(.bold))
    }

    let (remote, branch) = try await GitRepo.upstream(dirURL)
    let div = try await GitRepo.divergence(dirURL)
    print("    Upstream: \(remote)/\(branch)  (ahead=\(div.ahead), behind=\(div.behind))")

    if try await GitRepo.isDirty(dirURL) {
        let severity: ANSIColor = safe ? .red : .yellow
        printi("Working tree is dirty.".ansi(severity))

        if safe {
            printi("Safe mode enabled in run".ansi(.yellow))

            print()

            printi("Aborting to avoid losing changes.".ansi(.red))
            printi("Hint: commit/stash or run: git reset --hard && git pull --ff-only \(remote) \(branch)")

            print()

            printi("Leaving repository scope")
            return
        } else {
            printi("No '--safe' flag enabled, proceeding compile.".ansi(.cyan))
        }
    }

    // If remote changed OR we differ from upstream in any way, make local == upstream
    if isOutdated || div.ahead > 0 || div.behind > 0 {
        if div.ahead > 0 && safe {
            // Preserve prior safe behavior: don’t drop local commits in safe mode
            printi("Branch has diverged (ahead \(div.ahead), behind \(div.behind)).".ansi(.red))
            printi("Safe mode: not discarding local commits automatically.")

            print()

            printi("To preserve local history: rebase your local commits onto upstream:")
            printi(
                "git fetch --prune --tags && git rebase --autostash --rebase-merges \(remote)/\(branch)"
                .ansi(.cyan),
                times: 2
            )
            printi("To reset local changes to upstream: re-run without --safe, or do:")
            printi(
                "updater (no --safe flag)"
                .ansi(.cyan),
                times: 2
            )
            printi("or:")
            printi("git fetch --prune --tags && git reset --hard @{u} && git clean -fdx"
                .ansi(.cyan),
                times: 2
            )
            return
        }

        printi("Updating (resetting to upstream)…")
        try await GitRepo.hardResetToUpstream(dirURL, cleanUntracked: false)
        printi("Reset complete.")
    }

    if let compile = entry.compile {
        let obj_url = try BuildObjectConfiguration.traverseForBuildObjectPkl(from: dirURL)
        let obj = try BuildObjectConfiguration(from: obj_url)

        let v_release = obj.versions.release

        // soft try to get compiled.pkl
        let compl_url_soft = try? BuildObjectConfiguration.traverseForBuildObjectPkl(
            from: dirURL,
            maxDepth: 6,
            buildFile: "compiled.pkl"
        )

        var reasonToCompile = false

        if let compl_url_found = compl_url_soft {
            let compl_cfg = try CompiledLocalBuildObject(from: compl_url_found)
            let v_compiled = compl_cfg.version
            
            let c = v_compiled
            let r = v_release
            let builtIsBehind = (c.major, c.minor, c.patch) < (r.major, r.minor, r.patch)

            // if v_compiled == v_release { 
            if !builtIsBehind {
                printi("Built version seems up-to-date; skipping compile.")
            } else {
                reasonToCompile = true
                printi("Built version is now behind repository recompiling…")
                printi("compiled:   \(v_compiled.string(prefixStyle: .none))", times: 2)
                printi("release:    \(v_release.string(prefixStyle: .none))", times: 2)
            }
        } else {
            printi("No compiled.pkl detected; compiling…")
            reasonToCompile = true
        }

        if reasonToCompile {
            try await executeCompileSpec(compile, in: dirURL)
        }
    }

    if entry.relaunch?.enable == true {
        // try await relaunchApplication(dirURL, target: entry.relaunch?.target)
        try await ProcessEvaluator().relaunch(dirURL, target: entry.relaunch?.target)
    }

    print("")
}
