//
//  SDKVersion.swift
//  spacetimedb-swift-sdk
//
//  Codegen / SDK version pin. Codegen embeds the `spacetime-swift`
//  CLI version it was built with as a string in generated `Db.swift`;
//  the SDK validates that against
//  `SDKVersion.minimumCompatibleCodegenVersion` at `Db.attach(to:)`
//  time and throws if the codegen is too old to be safe.
//
//  Mirrors TS v3's `ensureMinimumVersionOrThrow(cliVersion)` —
//  prevents silent breakage when the wire layout or generated
//  protocol surface changes.
//

import Foundation

public enum SDKVersion {
    /// Current SDK release (semantic-version string). Bumped per
    /// release; codegen reads it as a static string and embeds the
    /// matching `spacetime-swift` CLI version into generated files.
    public static let current = "2.1.0"

    /// Minimum codegen-emitted version this SDK can consume. Generated
    /// files emitted by an older `spacetime-swift` CLI will refuse to
    /// attach. Bump in lockstep with breaking codegen-format changes.
    public static let minimumCompatibleCodegenVersion = "2.1.0"

    public enum Error: Swift.Error, CustomStringConvertible, Sendable {
        case incompatibleCodegen(found: String, required: String)

        public var description: String {
            switch self {
            case .incompatibleCodegen(let found, let required):
                return "spacetime-swift codegen version \(found) is older than the SDK's minimum supported codegen version \(required); regenerate with the bundled CLI"
            }
        }
    }

    /// Validate a codegen-embedded version string. Throws
    /// `Error.incompatibleCodegen` if `codegenVersion` parses to a
    /// SemVer triple older than `minimumCompatibleCodegenVersion`.
    /// Unparseable strings pass — the SDK errs on the side of letting
    /// non-conformant versions through.
    public static func ensureCompatible(codegenVersion: String) throws {
        guard let actual = Self.parse(codegenVersion),
              let minimum = Self.parse(minimumCompatibleCodegenVersion) else {
            return
        }
        if actual < minimum {
            throw Error.incompatibleCodegen(
                found: codegenVersion,
                required: minimumCompatibleCodegenVersion
            )
        }
    }

    /// Strict SemVer parser: `MAJOR.MINOR.PATCH`. Returns `nil` if any
    /// of the three components are non-numeric. Pre-release / build
    /// suffixes are ignored.
    static func parse(_ s: String) -> (Int, Int, Int)? {
        let core = s.split(separator: "-").first.map(String.init) ?? s
        let parts = core.split(separator: ".").map(String.init)
        guard parts.count >= 3,
              let major = Int(parts[0]),
              let minor = Int(parts[1]),
              let patch = Int(parts[2]) else {
            return nil
        }
        return (major, minor, patch)
    }
}
