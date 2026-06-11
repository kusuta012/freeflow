import XCTest
@testable import FreeFlowCore

final class ShortcutMatcherTests: XCTestCase {
    func testHoldModifierKeyActivatesAndDeactivates() {
        let hold = ShortcutBinding(
            keyCode: 63,
            keyDisplay: "Fn",
            modifiers: [],
            kind: .modifierKey,
            preset: nil
        )
        let configuration = ShortcutConfiguration(hold: hold, toggle: .disabled, copyAgain: .disabled)
        var state = ShortcutInputState()

        let down = ShortcutMatcher.reduce(
            state: state,
            event: .modifierChanged(keyCode: 63, isDown: true),
            configuration: configuration
        )
        XCTAssertEqual(down.emittedEvents, [.holdActivated])
        XCTAssertEqual(down.consumeDecision, .consume)
        state = down.state

        let up = ShortcutMatcher.reduce(
            state: state,
            event: .modifierChanged(keyCode: 63, isDown: false),
            configuration: configuration
        )
        XCTAssertEqual(up.emittedEvents, [.holdDeactivated])
        XCTAssertEqual(up.consumeDecision, .consume)
    }

    func testToggleKeyWithModifierActivatesOnKeyDown() {
        let toggle = ShortcutBinding(
            keyCode: 96,
            keyDisplay: "F5",
            modifiers: [.command],
            kind: .key,
            preset: nil
        )
        let configuration = ShortcutConfiguration(hold: .disabled, toggle: toggle, copyAgain: .disabled)
        var state = ShortcutInputState()

        state = ShortcutMatcher.reduce(
            state: state,
            event: .modifierSnapshot([55]),
            configuration: configuration
        ).state

        let keyDown = ShortcutMatcher.reduce(
            state: state,
            event: .keyChanged(keyCode: 96, isDown: true, isRepeat: false),
            configuration: configuration
        )
        XCTAssertEqual(keyDown.emittedEvents, [.toggleActivated])
        XCTAssertEqual(keyDown.consumeDecision, .consume)
    }

    func testCopyAgainFiresOnceOnLeadingEdge() {
        let copyAgain = ShortcutBinding(
            keyCode: 61,
            keyDisplay: "Right Option",
            modifiers: [],
            kind: .modifierKey,
            preset: nil
        )
        let configuration = ShortcutConfiguration(hold: .disabled, toggle: .disabled, copyAgain: copyAgain)
        var state = ShortcutInputState()

        let firstDown = ShortcutMatcher.reduce(
            state: state,
            event: .modifierChanged(keyCode: 61, isDown: true),
            configuration: configuration
        )
        XCTAssertEqual(firstDown.emittedEvents, [.copyAgainTriggered])
        state = firstDown.state

        let secondDown = ShortcutMatcher.reduce(
            state: state,
            event: .modifierChanged(keyCode: 61, isDown: true),
            configuration: configuration
        )
        XCTAssertTrue(secondDown.emittedEvents.isEmpty)
    }
}
