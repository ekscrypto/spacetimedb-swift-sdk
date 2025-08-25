//
//  DebugConfiguration.swift
//  spacetimedb-swift-sdk
//
//  Created by Dave Poirier on 2025-08-25.
//

import Foundation

/// Thread-safe debug configuration for SpacetimeDB SDK
public final class DebugConfiguration: @unchecked Sendable {
    /// Shared instance for debug configuration
    public static let shared = DebugConfiguration()
    
    private let lock = NSLock()
    private var _isEnabled: Bool = false
    
    private init() {}
    
    /// Thread-safe getter for debug enabled state
    public var isEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isEnabled
    }
    
    /// Thread-safe setter for debug enabled state
    public func setEnabled(_ enabled: Bool) {
        lock.lock()
        defer { lock.unlock() }
        _isEnabled = enabled
    }
    
    /// Convenience method to print debug messages
    public func log(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        print(message())
    }
}

/// Global convenience function for debug logging
public func debugLog(_ message: @autoclosure () -> String) {
    DebugConfiguration.shared.log(message())
}