import Foundation

/// Display and comparison forms of a project directory path.
public enum ProjectNaming {
    /// The path with symlinks resolved and no trailing slash, e.g. `/tmp/x/` → `/private/tmp/x`.
    /// Claude Code records its cwd symlink-resolved, so a project must be compared by this one
    /// spelling. (`URL.resolvingSymlinksInPath()` won't do: it strips `/private` again.) A path that
    /// can't be resolved, e.g. because it doesn't exist, is only standardized.
    public static func canonicalPath(_ path: String) -> String {
        let canonical: String
        if let resolved = realpath(path, nil) {
            canonical = String(cString: resolved)
            free(resolved)
        } else {
            canonical = URL(fileURLWithPath: path).standardizedFileURL.path
        }
        guard canonical.count > 1, canonical.hasSuffix("/") else { return canonical }
        return String(canonical.dropLast())
    }

    /// `/Users/me/dev/x` → `~/dev/x`.
    public static func abbreviatingHome(_ path: String, home: String = NSHomeDirectory()) -> String {
        if path == home { return "~" }
        guard path.hasPrefix(home + "/") else { return path }
        return "~" + String(path.dropFirst(home.count))
    }
}
