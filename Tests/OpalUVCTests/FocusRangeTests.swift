import Testing
@testable import OpalUVC

@Suite struct FocusRangeTests {
    @Test func invertedRangeThrowsInvalidRange() {
        do {
            _ = try Connection.range(minimum: 10, maximum: 5)
            Issue.record("expected invalidRange, got a range of 10...5")
        } catch UVCError.invalidRange(let minimum, let maximum) {
            #expect(minimum == 10)
            #expect(maximum == 5)
        } catch {
            Issue.record("expected invalidRange, got \(error)")
        }
    }

    @Test func normalRange() throws {
        let range = try Connection.range(minimum: 10, maximum: 20)
        #expect(range == 10...20)
    }

    @Test func singlePointRange() throws {
        let range = try Connection.range(minimum: 30, maximum: 30)
        #expect(range == 30...30)
    }
}