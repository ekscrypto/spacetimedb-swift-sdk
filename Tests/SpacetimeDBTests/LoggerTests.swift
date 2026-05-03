import Testing
import Foundation
@testable import SpacetimeDB

@Suite("Logger redaction + level gating")
struct LoggerTests {

    // MARK: Redaction

    @Test func redactsBearerToken() {
        let input = "Authorization: Bearer eyJhbGciOiJI.payload.sig"
        let output = Logger.redact(input)
        #expect(output == "Authorization=*** Bearer ***" || output == "Authorization: Bearer ***" || !output.contains("eyJhbGciOiJI.payload.sig"))
        // The exact format varies based on which regex fires first;
        // the only contract we guarantee is the JWT body is gone.
    }

    @Test func redactsTokenKeyValueAssignments() {
        let input = "connecting with token=abc123secret and confirmed_reads=true"
        let output = Logger.redact(input)
        #expect(!output.contains("abc123secret"))
        #expect(output.contains("token=***"))
        #expect(output.contains("confirmed_reads=true"))
    }

    @Test func redactsAuthorizationKeyValuePair() {
        let input = "headers: { authorization: jwt.eyabc.sig }"
        let output = Logger.redact(input)
        #expect(!output.contains("jwt.eyabc.sig"))
        #expect(output.contains("***"))
    }

    @Test func redactsCommonSecretFieldNames() {
        for key in ["password", "secret", "api_key", "refreshToken", "accessToken"] {
            let input = "\(key)=verySecret123"
            let output = Logger.redact(input)
            #expect(!output.contains("verySecret123"), "Failed to redact key '\(key)' — got: \(output)")
        }
    }

    @Test func redactionLeavesBenignTextAlone() {
        let input = "subscribed to user table at offset 42"
        let output = Logger.redact(input)
        #expect(output == input)
    }

    // MARK: Level gating

    @Test func levelComparisonsOrderedCorrectly() {
        #expect(Logger.Level.error < Logger.Level.warn)
        #expect(Logger.Level.warn  < Logger.Level.info)
        #expect(Logger.Level.info  < Logger.Level.debug)
        #expect(Logger.Level.debug < Logger.Level.trace)
    }

    @Test func loggerConfigurationLevelIsPersistent() {
        let saved = LoggerConfiguration.shared.level
        defer { LoggerConfiguration.shared.level = saved }

        LoggerConfiguration.shared.level = .trace
        #expect(LoggerConfiguration.shared.level == .trace)

        LoggerConfiguration.shared.level = .error
        #expect(LoggerConfiguration.shared.level == .error)
    }
}
