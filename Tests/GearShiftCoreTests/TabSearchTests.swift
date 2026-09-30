@testable import GearShiftCore

func runTabSearchTests() {
    /// Feeds the titles in order (nil = the title didn't change after a switch) and returns the
    /// search once it's done, or after the last title.
    func scan(_ target: String, _ titles: [String?], limit: Int = TabSearch.defaultLimit) -> (TabSearch, [TabSearch.Step]) {
        var search = TabSearch(target: target, limit: limit)
        var steps: [TabSearch.Step] = []
        for title in titles {
            let step = search.observe(title)
            steps.append(step)
            if step == .done { break }
        }
        return (search, steps)
    }

    suite("TabSearch: keeps going after a match, until the tabs wrap") {
        // Tabs: Option help, Shiftcc app, ~ — then back to the first two.
        let (search, steps) = scan("Shiftcc app", ["✳ Option help", "◑ Shiftcc app", "~", "✳ Option help", "◐ Shiftcc app"])
        expectEqual(steps, [.next, .next, .next, .next, .done])
        expectEqual(search.matchOffsets, [1])
        expectEqual(search.cycleLength, 3)
        expectEqual(search.nextPresses, 4)
        expect(search.isComplete, "every tab was seen")
        expectEqual(search.pressesBackToStart, 1)  // 4 presses in a cycle of 3
    }

    suite("TabSearch: a match on the first tab still checks the rest") {
        let (search, steps) = scan("Shiftcc app", ["◐ Shiftcc app", "~", "◑ Shiftcc app", "~"])
        expectEqual(steps, [.next, .next, .next, .done])
        expectEqual(search.matchOffsets, [0])
        expectEqual(search.cycleLength, 2)
    }

    suite("TabSearch: a longer cycle") {
        let titles: [String?] = ["a", "b", "✳ c", "d", "e", "a", "b"]
        let (search, steps) = scan("c", titles)
        expectEqual(steps, [.next, .next, .next, .next, .next, .next, .done])
        expectEqual(search.matchOffsets, [2])
        expectEqual(search.cycleLength, 5)
        expectEqual(search.nextPresses, 6)
        expectEqual(search.pressesBackToStart, 1)
    }

    suite("TabSearch: duplicate non-matching titles (two ~ tabs) aren't a wrap") {
        // Tabs: ~, x, ~, target. The first title recurs at offset 2, but the second doesn't follow.
        let (search, steps) = scan("target", ["~", "x", "~", "✳ target", "~", "x"])
        expectEqual(steps, [.next, .next, .next, .next, .next, .done])
        expectEqual(search.matchOffsets, [3])
        expectEqual(search.cycleLength, 4)
        expectEqual(search.pressesBackToStart, 1)
    }

    suite("TabSearch: two tabs showing the target are both found") {
        let (twoApart, _) = scan("T", ["✳ T", "a", "◑ T", "b", "✳ T", "a"])
        expectEqual(twoApart.matchOffsets, [0, 2])
        expectEqual(TabSearch.decide([twoApart]), .duplicate)

        // T, a, T: the switch from the last T back to the first doesn't change the title.
        let (wrapIntoSame, steps) = scan("T", ["✳ T", "a", "✳ T", nil])
        expectEqual(steps, [.next, .next, .next, .done])
        expectEqual(wrapIntoSame.matchOffsets, [0, 2])
    }

    suite("TabSearch: a title that doesn't change ends the window (single tab)") {
        let (single, steps) = scan("T", ["✳ T", nil])
        expectEqual(steps, [.next, .done])
        expectEqual(single.matchOffsets, [0])
        expect(single.isComplete, "one tab, all seen")
        expectEqual(single.cycleLength, nil)
        // Unknown whether the last switch moved: go back as many times as we went forward.
        expectEqual(single.pressesBackToStart, 1)

        let (other, _) = scan("T", ["✳ Other", nil])
        expectEqual(other.matchOffsets, [])
        let (none, noneSteps) = scan("T", [nil])
        expectEqual(noneSteps, [.done])
        expectEqual(none.matchOffsets, [])
        expectEqual(none.pressesBackToStart, 0)
    }

    suite("TabSearch: plain titles never match") {
        let (search, _) = scan("GearShift", ["GearShift", "-zsh", "(venv) GearShift", "GearShift", "-zsh"])
        expectEqual(search.matchOffsets, [])
        expectEqual(TabSearch.decide([search]), .notFound)
    }

    suite("TabSearch: the limit stops a window and leaves it incomplete") {
        let (limited, steps) = scan("T", ["a", "b", "c", "d"], limit: 3)
        expectEqual(steps, [.next, .next, .next, .done])
        expect(!limited.isComplete, "stopped by the limit")
        expectEqual(limited.nextPresses, 3)
        expectEqual(limited.pressesBackToStart, 3)

        var defaultLimit = TabSearch(target: "T")
        let outcomes = (0...TabSearch.defaultLimit).map { defaultLimit.observe("tab \($0)") }
        expectEqual(outcomes.dropLast().allSatisfy { $0 == .next }, true)
        expectEqual(outcomes.last, .done)
    }

    suite("TabSearch: decide across windows") {
        let (hit, _) = scan("T", ["a", "✳ T", "a", "✳ T"])
        let (miss, _) = scan("T", ["b", nil])
        let (alsoHit, _) = scan("T", ["✳ T", nil])
        let (cutShort, _) = scan("T", ["c", "d", "e"], limit: 2)
        expectEqual(TabSearch.decide([miss, hit]), .found(window: 1, offset: 1))
        expectEqual(TabSearch.decide([miss]), .notFound)
        expectEqual(TabSearch.decide([]), .notFound)
        expectEqual(TabSearch.decide([hit, alsoHit]), .duplicate)
        expectEqual(TabSearch.decide([hit, cutShort]), .incomplete)
        expectEqual(TabSearch.decide([miss, cutShort]), .notFound)
    }
}
