import Testing
import Foundation
@testable import SpacetimeDB

@Suite("SDKVersion compatibility check")
struct SDKVersionTests {

    @Test func parsesValidSemver() {
        let v = SDKVersion.parse("2.1.0")
        #expect(v?.0 == 2)
        #expect(v?.1 == 1)
        #expect(v?.2 == 0)
    }

    @Test func parsesPrereleaseSuffix() {
        let v = SDKVersion.parse("3.0.1-beta.4")
        #expect(v?.0 == 3)
        #expect(v?.1 == 0)
        #expect(v?.2 == 1)
    }

    @Test func parserRejectsNonNumeric() {
        #expect(SDKVersion.parse("abc") == nil)
        #expect(SDKVersion.parse("1.2") == nil)
        #expect(SDKVersion.parse("1.x.0") == nil)
    }

    @Test func ensureCompatiblePassesForCurrentVersion() throws {
        try SDKVersion.ensureCompatible(codegenVersion: SDKVersion.minimumCompatibleCodegenVersion)
    }

    @Test func ensureCompatiblePassesForNewerCodegen() throws {
        try SDKVersion.ensureCompatible(codegenVersion: "99.99.99")
    }

    @Test func ensureCompatibleThrowsForOlderCodegen() {
        do {
            try SDKVersion.ensureCompatible(codegenVersion: "0.0.1")
            Issue.record("Expected ensureCompatible to throw")
        } catch SDKVersion.Error.incompatibleCodegen(let found, let required) {
            #expect(found == "0.0.1")
            #expect(required == SDKVersion.minimumCompatibleCodegenVersion)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func ensureCompatibleSilentlyPassesForUnparseableVersions() throws {
        // Errs on the side of letting unrecognized versions through.
        try SDKVersion.ensureCompatible(codegenVersion: "garbage")
    }
}
