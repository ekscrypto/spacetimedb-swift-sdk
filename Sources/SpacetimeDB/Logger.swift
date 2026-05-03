//
//  Logger.swift
//  spacetimedb-swift-sdk
//
//  Namespaced logger with secret redaction. Mirrors the TS v3 SDK's
//  `stdbLogger`: every emitted message gets a `[<namespace>]` prefix
//  and goes through a redaction pass that masks bearer tokens and
//  any field whose key matches the redacted-keys allowlist below.
//
//  The library does not own user logging; this surface is only used
//  internally by the SDK and exposed publicly so that applications
//  embedding the SDK can mirror the same redaction rules. Replacing
//  the sink is intentionally not a public API yet — filed as a
//  follow-up if needed.
//

import Foundation

public struct Logger: Sendable {
    public enum Level: Int, Sendable, Comparable {
        case error = 0
        case warn  = 1
        case info  = 2
        case debug = 3
        case trace = 4

        public static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public let namespace: String

    public init(namespace: String) {
        self.namespace = namespace
    }

    public func error(_ message: @autoclosure () -> String) { emit(.error, message()) }
    public func warn(_ message: @autoclosure () -> String)  { emit(.warn,  message()) }
    public func info(_ message: @autoclosure () -> String)  { emit(.info,  message()) }
    public func debug(_ message: @autoclosure () -> String) { emit(.debug, message()) }
    public func trace(_ message: @autoclosure () -> String) { emit(.trace, message()) }

    private func emit(_ level: Level, _ message: String) {
        guard level <= LoggerConfiguration.shared.level else { return }
        let line = "[\(namespace)] \(label(level)): \(Logger.redact(message))\n"
        FileHandle.standardError.write(Data(line.utf8))
    }

    private func label(_ level: Level) -> String {
        switch level {
        case .error: return "error"
        case .warn:  return "warn"
        case .info:  return "info"
        case .debug: return "debug"
        case .trace: return "trace"
        }
    }

    // MARK: Redaction

    /// Replace likely-secret values with `***` so logs are safe to ship
    /// to telemetry or paste into tickets. Heuristics:
    ///   • `key=value` and `key: value` for keys in `redactedKeys`
    ///   • `Bearer <jwt>` / `Authorization: Bearer <jwt>`
    ///   • `Identity(0xabcdef…)` / 64-char lowercase hex sequences
    ///     (not redacted by default — identities aren't secret, just PII;
    ///     callers can opt in by passing a transformed message).
    public static func redact(_ message: String) -> String {
        var result = message

        // Bearer token in Authorization header.
        result = result.replacingOccurrences(
            of: #"(?i)Bearer\s+[A-Za-z0-9._\-+/=]+"#,
            with: "Bearer ***",
            options: .regularExpression
        )

        // key=value or key: value for sensitive keys.
        for key in redactedKeys {
            let escapedKey = NSRegularExpression.escapedPattern(for: key)
            let pattern = #"(?i)(\#(escapedKey))\s*[:=]\s*([^\s,;)]+)"#
            result = result.replacingOccurrences(
                of: pattern,
                with: "$1=***",
                options: .regularExpression
            )
        }

        return result
    }

    /// Keys (case-insensitive) whose values are masked when found in a
    /// `key=value` or `key: value` substring.
    public static let redactedKeys: [String] = [
        "token",
        "authorization",
        "auth_token",
        "authToken",
        "access_token",
        "accessToken",
        "refresh_token",
        "refreshToken",
        "password",
        "secret",
        "api_key",
        "apiKey",
    ]
}

/// Process-wide log level. Defaults to `.warn` so day-to-day SDK use
/// stays quiet; bump it via `LoggerConfiguration.shared.level = .debug`
/// for SDK-internal diagnostics.
public final class LoggerConfiguration: @unchecked Sendable {
    public static let shared = LoggerConfiguration()

    private let lock = NSLock()
    private var _level: Logger.Level = .warn

    private init() {}

    public var level: Logger.Level {
        get {
            lock.lock(); defer { lock.unlock() }
            return _level
        }
        set {
            lock.lock(); defer { lock.unlock() }
            _level = newValue
        }
    }
}

/// Namespace used by SDK-internal logs. Application code should pick
/// its own namespace via `Logger(namespace: "myapp")`.
public let stdbLogger = Logger(namespace: "spacetimedb")
