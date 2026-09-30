import Foundation
@testable import GearShiftCore

func runProjectNamingTests() {
    suite("ProjectNaming") {
        expectEqual(ProjectNaming.abbreviatingHome("/Users/me/dev/x", home: "/Users/me"), "~/dev/x")
        expectEqual(ProjectNaming.abbreviatingHome("/Users/me", home: "/Users/me"), "~")
        expectEqual(ProjectNaming.abbreviatingHome("/Users/meg/x", home: "/Users/me"), "/Users/meg/x")

        // /var is a symlink to /private/var; Claude Code records the resolved cwd.
        let temporary = makeTemporaryDirectory().path
        expect(temporary.hasPrefix("/var/folders/"), "temporary directory \(temporary)")
        expectEqual(ProjectNaming.canonicalPath(temporary), "/private" + temporary)
        expectEqual(ProjectNaming.canonicalPath(temporary + "/"), "/private" + temporary)
        expectEqual(ProjectNaming.canonicalPath("/nonexistent/a/../b/"), "/nonexistent/b")
        expectEqual(ProjectNaming.canonicalPath("/"), "/")
    }
}
