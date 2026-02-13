import XCTest
@testable import TextFix

final class HotkeySpecTests: XCTestCase {
    func testParseCmdShiftG() {
        let spec = HotkeySpec.parse("<cmd>+<shift>+g")
        XCTAssertNotNil(spec)
        XCTAssertEqual(spec?.keycode, 5) // 'g' keycode
    }

    func testParseCmdShiftH() {
        let spec = HotkeySpec.parse("<cmd>+<shift>+h")
        XCTAssertNotNil(spec)
        XCTAssertEqual(spec?.keycode, 4) // 'h' keycode
    }

    func testParseWithoutBrackets() {
        let spec = HotkeySpec.parse("cmd+shift+g")
        XCTAssertNotNil(spec)
        XCTAssertEqual(spec?.keycode, 5)
    }

    func testParseSpecialKey() {
        let spec = HotkeySpec.parse("<cmd>+<f1>")
        XCTAssertNotNil(spec)
        XCTAssertEqual(spec?.keycode, 122) // F1 keycode
    }

    func testParseInvalidReturnsNil() {
        XCTAssertNil(HotkeySpec.parse("<cmd>+<shift>"))
        XCTAssertNil(HotkeySpec.parse(""))
    }

    func testParseAltCtrl() {
        let spec = HotkeySpec.parse("<ctrl>+<alt>+a")
        XCTAssertNotNil(spec)
        XCTAssertEqual(spec?.keycode, 0) // 'a' keycode
    }
}
