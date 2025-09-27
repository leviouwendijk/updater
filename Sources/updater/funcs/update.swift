import Foundation
import Interfaces
import plate

@inline(__always)
private func isDirty(_ dir: URL) async throws -> Bool {
    let s = try await sh(.zsh, "git", ["status","--porcelain"], cwd: dir)
        .stdoutText().trimmingCharacters(in: .whitespacesAndNewlines)
    return !s.isEmpty
}

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

    if try await isDirty(dirURL) {
        let severity: ANSIColor = safe ? .red : .yellow
        print("    Working tree is dirty. Aborting to avoid losing changes.".ansi(severity))

        if safe {
            printi("Safe mode enabled in run".ansi(.yellow))

            print()
            print("    Aborting to avoid losing changes.".ansi(.red))
            print("    Hint: commit/stash or run: git reset --hard && git pull --ff-only \(remote) \(branch)")
            print()

            printi("Leaving repository scope")
            return
        }
    }

    if isOutdated {
        print("    Updating…")
        _ = try await sh(.zsh, "git", ["reset","--hard","HEAD"], cwd: dirURL)

        // Pull rules:
        // - behind>0 && ahead==0  → fast-forward only
        // - behind>0 && ahead>0   → diverged; bail (don’t auto-merge/rebase here)
        // - behind==0             → already at/after upstream; skip pull
        if div.behind > 0 && div.ahead == 0 {
            _ = try await sh(.zsh, "git", ["pull","--ff-only", remote, branch], cwd: dirURL)
        } else if div.behind > 0 && div.ahead > 0 {
            print("    Branch has diverged (ahead \(div.ahead), behind \(div.behind)).".ansi(.red))
            print("    Resolve manually: git pull --rebase \(remote) \(branch)  (or merge), then re-run.")
            return
        } else {
            print("    Local branch is ahead of upstream; skipping pull.")
        }
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
        try await relaunchApplication(dirURL, target: entry.relaunch?.target)
    }

    print("")
}
