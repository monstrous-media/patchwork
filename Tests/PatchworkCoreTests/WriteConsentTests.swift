import XCTest
@testable import PatchworkCore

/// The CLI's guard for commands that overwrite what the M1 stores (restore, write, send --write,
/// global --send / --load). SO-02: no write without --yes or an interactive confirmation.
final class WriteConsentTests: XCTestCase {

    func testYesFlagProceedsWithoutPrompting() {
        var prompted = false
        let d = WriteConsent.decide(yes: true, interactive: false, description: "x") { _ in prompted = true; return nil }
        XCTAssertEqual(d, .proceed)
        XCTAssertFalse(prompted, "--yes must not prompt (it exists for scripts and agents)")
    }

    func testNonInteractiveWithoutYesIsRefusedAndNeverPrompts() {
        var prompted = false
        let d = WriteConsent.decide(yes: false, interactive: false, description: "x") { _ in prompted = true; return "y" }
        guard case .refused(let why) = d else { return XCTFail("expected a refusal, got \(d)") }
        XCTAssertTrue(why.contains(WriteConsent.refusalMessage), why)
        XCTAssertTrue(why.contains("--yes"), "the refusal must say how to proceed")
        XCTAssertFalse(prompted, "a pipe or CI job can't answer, so it must not be asked")
    }

    func testInteractiveYesProceedsAndShowsWhatWillBeOverwritten() {
        var shown = ""
        let d = WriteConsent.decide(yes: false, interactive: true, description: "write 3 programs to I00–I02") { q in shown = q; return " Y\n" }
        XCTAssertEqual(d, .proceed)
        XCTAssertTrue(shown.contains("write 3 programs to I00–I02"))
        XCTAssertTrue(shown.contains("[y/N]"))
    }

    func testInteractiveAnythingElseIsRefused() {
        let answers: [String?] = ["n", "", "yes please", "Y es", nil]
        for answer in answers {
            let d = WriteConsent.decide(yes: false, interactive: true, description: "x") { _ in answer }
            guard case .refused = d else { return XCTFail("answer \(String(describing: answer)) must not proceed") }
        }
    }

    func testSlotRangesNameEverySlotCompactly() {
        let label = { String(format: "I%02d", $0) }
        XCTAssertEqual(WriteConsent.slotRanges([0, 1, 2, 5, 7, 8], label: label), "I00–I02, I05, I07–I08")
        XCTAssertEqual(WriteConsent.slotRanges(Array(0..<100), label: label), "I00–I99")
        XCTAssertEqual(WriteConsent.slotRanges([57], label: label), "I57")
        XCTAssertEqual(WriteConsent.slotRanges([3, 3, 1], label: label), "I01, I03")
        XCTAssertEqual(WriteConsent.slotRanges([], label: label), "")
    }

    func testFullWordYesIsAccepted() {
        XCTAssertEqual(WriteConsent.decide(yes: false, interactive: true, description: "x") { _ in "yes" }, .proceed)
    }
}
