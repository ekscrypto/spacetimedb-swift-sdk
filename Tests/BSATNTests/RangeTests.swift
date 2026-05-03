import Testing
import Foundation
@testable import BSATN

@Suite("Phase 15: Range + Bound Tests")
struct RangeTests {

    // MARK: Bound

    @Test func unboundedFlag() {
        #expect(Bound<Int>.unbounded.isUnbounded)
        #expect(!Bound<Int>.inclusive(1).isUnbounded)
        #expect(!Bound<Int>.exclusive(1).isUnbounded)
    }

    @Test func valueAccessor() {
        #expect(Bound<Int>.inclusive(5).value == 5)
        #expect(Bound<Int>.exclusive(5).value == 5)
        #expect(Bound<Int>.unbounded.value == nil)
    }

    @Test func inclusiveFlag() {
        #expect(Bound<Int>.inclusive(5).isInclusive)
        #expect(!Bound<Int>.exclusive(5).isInclusive)
        #expect(!Bound<Int>.unbounded.isInclusive)
    }

    // MARK: Range constructors

    @Test func equalRangeContainsOnlyExactValue() {
        let r = Range<Int>.equal(7)
        #expect(r.contains(7))
        #expect(!r.contains(6))
        #expect(!r.contains(8))
    }

    @Test func startingAtIsClosedFromLow() {
        let r = Range<Int>.startingAt(10)
        #expect(r.contains(10))
        #expect(r.contains(1_000_000))
        #expect(!r.contains(9))
    }

    @Test func startingAfterExcludesLow() {
        let r = Range<Int>.startingAfter(10)
        #expect(!r.contains(10))
        #expect(r.contains(11))
    }

    @Test func endingAtIsClosedToHigh() {
        let r = Range<Int>.endingAt(10)
        #expect(r.contains(10))
        #expect(r.contains(-1_000_000))
        #expect(!r.contains(11))
    }

    @Test func endingBeforeExcludesHigh() {
        let r = Range<Int>.endingBefore(10)
        #expect(!r.contains(10))
        #expect(r.contains(9))
    }

    @Test func closedIncludesBothEndpoints() {
        let r = Range<Int>.closed(from: 1, to: 5)
        #expect(r.contains(1))
        #expect(r.contains(5))
        #expect(!r.contains(0))
        #expect(!r.contains(6))
    }

    @Test func halfOpenExcludesUpperEndpoint() {
        let r = Range<Int>.halfOpen(from: 1, to: 5)
        #expect(r.contains(1))
        #expect(!r.contains(5))
        #expect(r.contains(4))
    }

    @Test func unboundedAcceptsAnything() {
        let r = Range<Int>.unbounded
        #expect(r.contains(.min))
        #expect(r.contains(0))
        #expect(r.contains(.max))
    }

    @Test func equatableAcrossSameValues() {
        #expect(Range<Int>.equal(7) == Range<Int>.equal(7))
        #expect(Range<Int>.closed(from: 1, to: 3) != Range<Int>.halfOpen(from: 1, to: 3))
    }

    @Test func worksWithStringKeys() {
        let r = Range<String>.startingAt("alice")
        #expect(r.contains("alice"))
        #expect(r.contains("bob"))
        #expect(!r.contains("aa"))
    }
}
