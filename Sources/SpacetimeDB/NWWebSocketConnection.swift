//
//  NWWebSocketConnection.swift
//  spacetimedb-swift-sdk
//
//  WebSocket transport over a Network.framework TCP/TLS connection, with
//  the RFC 6455 handshake and framing implemented in-package.
//
//  Why not the platform websocket APIs: neither can talk to every
//  SpacetimeDB deployment. `URLSessionWebSocketTask` negotiates ALPN and,
//  when the server selects HTTP/2, attempts the WebSocket over the
//  extended CONNECT protocol (RFC 8441) with no public opt-out — servers
//  fronted by an nginx that advertises h2 but lacks
//  SETTINGS_ENABLE_CONNECT_PROTOCOL abort it (POSIX 57 "Socket is not
//  connected"). `NWProtocolWebSocket` always emits the upgrade token
//  `Upgrade: WebSocket`, which SpacetimeDB's HTTP layer rejects
//  case-sensitively with 426 — it requires the lowercase `websocket`.
//  A plain `NWConnection` with TLS offers no ALPN (the server falls back
//  to HTTP/1.1), and writing the handshake ourselves pins the exact
//  header values. Client frames are masked per RFC 6455 §5.3; server
//  frames arrive unmasked; ping/close are handled inline.
//
//  The byte-level shape mirrors the working reference clients
//  (tokio-tungstenite in the BitCraft mirror stack):
//  `GET <path> HTTP/1.1` + `Host`, `Upgrade: websocket`,
//  `Connection: Upgrade`, `Sec-WebSocket-Key/Version/Protocol`,
//  `Authorization`.
//
//  Created by Dave Poirier on 2026-09-26.
//

import Foundation
import Network

internal final class NWWebSocketConnection: @unchecked Sendable {

    enum TransportError: Error, Equatable {
        case connectionFailed(String)
        case handshakeFailed(String)
        case timeout
        case closed
    }

    enum Event: Sendable {
        /// The HTTP/1.1 upgrade completed — the WebSocket is open.
        case connected
        /// The peer (or the transport) closed the connection.
        case closed
        /// The connection failed.
        case failed(String)
    }

    private let connection: NWConnection
    private let lock = NSLock()
    private var frames: [Data] = []
    private var waiters: [CheckedContinuation<Data?, Error>] = []
    /// Terminal state; nil while the connection is live. `.some(nil)` is a
    /// clean close (pending receives resume with nil).
    private var terminal: TransportError??
    private var eventHandler: (@Sendable (Event) -> Void)?
    private var handshakeComplete = false
    private var inbound = Data()
    private var openTimeout: DispatchWorkItem?
    private let timeoutQueue = DispatchQueue(label: "spacetimedb.swift-sdk.websocket.timeout")
    private let queue = DispatchQueue(label: "spacetimedb.swift-sdk.websocket")

    init(url: URL, headers: [(name: String, value: String)] = [], subprotocol wsSubprotocol: String? = nil) {
        self.connection = Self.makeConnection(url: url)
        self.handshake = Self.makeHandshakeRequest(
            url: url, headers: headers, subprotocol: wsSubprotocol
        )
    }

    private let handshake: String

    private static func makeConnection(url: URL) -> NWConnection {
        let host = url.host ?? ""
        let port = NWEndpoint.Port(rawValue: UInt16(url.port ?? (url.scheme?.lowercased() == "ws" ? 80 : 443))) ?? 443
        let params: NWParameters
        if url.scheme?.lowercased() == "ws" || url.scheme?.lowercased() == "http" {
            params = NWParameters.tcp
        } else {
            // Plain TLS, deliberately without ALPN: servers that speak h2
            // fall back to HTTP/1.1 for this connection (see class docs).
            params = NWParameters(tls: NWProtocolTLS.Options())
        }
        return NWConnection(host: NWEndpoint.Host(host), port: port, using: params)
    }

    /// The literal upgrade request. Header values are pinned exactly; in
    /// particular `Upgrade: websocket` (lowercase) — the server side of
    /// SpacetimeDB matches the token case-sensitively.
    private static func makeHandshakeRequest(
        url: URL,
        headers: [(name: String, value: String)],
        subprotocol wsSubprotocol: String?
    ) -> String {
        var path = url.path.isEmpty ? "/" : url.path
        if let query = url.query {
            path += "?\(query)"
        }
        let host = url.port.map { "\(url.host ?? ""):\($0)" } ?? (url.host ?? "")
        var request = "GET \(path) HTTP/1.1\r\n"
        request += "Host: \(host)\r\n"
        request += "Upgrade: websocket\r\n"
        request += "Connection: Upgrade\r\n"
        let key = Data((0..<16).map { _ in UInt8.random(in: 0...255) }).base64EncodedString()
        request += "Sec-WebSocket-Key: \(key)\r\n"
        request += "Sec-WebSocket-Version: 13\r\n"
        if let wsSubprotocol {
            request += "Sec-WebSocket-Protocol: \(wsSubprotocol)\r\n"
        }
        for (name, value) in headers {
            request += "\(name): \(value)\r\n"
        }
        request += "\r\n"
        return request
    }

    // MARK: - Public surface

    /// Transport lifecycle events; set before `open()`.
    func onEvent(_ handler: @escaping @Sendable (Event) -> Void) {
        lock.withLock { eventHandler = handler }
    }

    /// Start the connection. `timeout` bounds the time to `.connected`
    /// (TCP + TLS + the HTTP/1.1 upgrade).
    func open(timeout: TimeInterval) {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.sendHandshake()
                self.receiveNextChunk()
            case .failed(let error):
                self.fail(.connectionFailed(String(describing: error)))
            case .cancelled:
                self.finish(nil)
                self.emitEvent(.closed)
            default:
                break
            }
        }
        let timeoutWork = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let timedOut: Bool = self.lock.withLock {
                if self.handshakeComplete { return false }
                if self.terminal == nil { self.terminal = .some(TransportError.timeout) }
                return true
            }
            if timedOut {
                self.connection.cancel()
            }
        }
        lock.withLock { openTimeout = timeoutWork }
        timeoutQueue.asyncAfter(deadline: .now() + timeout, execute: timeoutWork)
        connection.start(queue: queue)
    }

    /// Send one binary (BSATN) message as a single masked frame. Sends
    /// issued before the upgrade completes are queued and flushed in order
    /// once the 101 lands — injecting frame bytes into the HTTP exchange
    /// would break the handshake.
    func send(_ data: Data) async throws {
        let frame = Self.frame(opcode: .binary, payload: data, masked: true)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let ready: Bool = lock.withLock {
                if let terminal, case .some(let error) = terminal {
                    continuation.resume(throwing: error)
                    return true
                }
                if terminal != nil {
                    continuation.resume(throwing: TransportError.closed)
                    return true
                }
                if handshakeComplete { return false }
                pendingSends.append((frame, continuation))
                return true
            }
            if !ready {
                Task { [weak self] in
                    guard let self else {
                        continuation.resume(throwing: TransportError.closed)
                        return
                    }
                    do {
                        try await self.sendRaw(frame)
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    private var pendingSends: [(Data, CheckedContinuation<Void, Error>)] = []

    private func flushPendingSends() {
        let pending: [(Data, CheckedContinuation<Void, Error>)] = lock.withLock {
            let batch = pendingSends
            pendingSends.removeAll()
            return batch
        }
        for (frame, continuation) in pending {
            connection.send(content: frame, contentContext: .defaultMessage, isComplete: true, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    /// Await the next binary message. Returns nil once the connection has
    /// closed cleanly; throws once it has failed.
    func receive() async throws -> Data? {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                if !frames.isEmpty {
                    continuation.resume(returning: frames.removeFirst())
                } else if let terminal {
                    if case .some(let error) = terminal {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: nil)
                    }
                } else {
                    waiters.append(continuation)
                }
            }
        }
    }

    func close() {
        // Best-effort close handshake: emit a Close frame, then tear down.
        let frame = Self.frame(opcode: .close, payload: Data(), masked: true)
        connection.send(content: frame, contentContext: .defaultMessage, isComplete: true, completion: .contentProcessed { [weak self] _ in
            self?.connection.cancel()
        })
        lock.withLock { openTimeout?.cancel() }
        // If the connection is not yet established, cancel directly.
        if !lock.withLock({ handshakeComplete }) {
            connection.cancel()
        }
    }

    // MARK: - Handshake

    private func sendHandshake() {
        connection.send(
            content: Data(handshake.utf8),
            contentContext: .defaultMessage,
            isComplete: true,
            completion: .contentProcessed { [weak self] error in
                if let error {
                    self?.fail(.connectionFailed(String(describing: error)))
                }
            }
        )
    }

    private func receiveNextChunk() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, _, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.inbound.append(data)
                self.consumeInbound()
            }
            if let error {
                self.fail(.connectionFailed(String(describing: error)))
                return
            }
            if let data, !data.isEmpty {
                self.receiveNextChunk()
            } else {
                // nil data without an error: end of stream.
                self.finish(nil)
                self.emitEvent(.closed)
            }
        }
    }

    /// Drives the inbound buffer through its current mode: handshake
    /// response first, then RFC 6455 frames.
    private func consumeInbound() {
        if !lock.withLock({ handshakeComplete }) {
            guard let range = inbound.range(of: Data("\r\n\r\n".utf8)) else { return }
            let head = String(data: inbound[..<range.lowerBound], encoding: .utf8) ?? ""
            inbound.removeSubrange(..<range.upperBound)
            guard head.hasPrefix("HTTP/1.1 101") || head.hasPrefix("HTTP/1.0 101") else {
                let status = head.split(separator: "\r\n").first.map(String.init) ?? "no status"
                debugLog(">>> websocket transport handshake rejected: \(status)")
                fail(.handshakeFailed("server refused the upgrade: \(status)"))
                connection.cancel()
                return
            }
            let wasComplete: Bool = lock.withLock {
                if terminal != nil { return false }
                handshakeComplete = true
                openTimeout?.cancel()
                return true
            }
            if wasComplete {
                emitEvent(.connected)
                flushPendingSends()
            }
        }
        parseFrames()
    }

    // MARK: - RFC 6455 framing

    private enum Opcode: UInt8 {
        case continuation = 0x0
        case text = 0x1
        case binary = 0x2
        case close = 0x8
        case ping = 0x9
        case pong = 0xA
    }

    /// Assembles complete messages from `inbound`. Control frames are
    /// handled inline; fragmented messages accumulate until their final
    /// fragment.
    private func parseFrames() {
        while true {
            guard inbound.count >= 2 else { return }
            let b0 = inbound[inbound.startIndex]
            let b1 = inbound[inbound.index(after: inbound.startIndex)]
            let fin = b0 & 0x80 != 0
            guard b0 & 0x70 == 0 else {
                fail(.connectionFailed("reserved bits set in websocket frame"))
                connection.cancel()
                return
            }
            guard let opcode = Opcode(rawValue: b0 & 0x0F) else {
                fail(.connectionFailed("unknown websocket opcode \(b0 & 0x0F)"))
                connection.cancel()
                return
            }
            let masked = b1 & 0x80 != 0
            var length = Int(b1 & 0x7F)
            var offset = inbound.startIndex
            inbound.formIndex(&offset, offsetBy: 2)
            if length == 126 {
                guard inbound.distance(from: offset, to: inbound.endIndex) >= 2 else { return }
                length = Int(inbound[offset]) << 8 | Int(inbound[inbound.index(after: offset)])
                inbound.formIndex(&offset, offsetBy: 2)
            } else if length == 127 {
                guard inbound.distance(from: offset, to: inbound.endIndex) >= 8 else { return }
                var value = 0
                for i in 0..<8 {
                    value = value << 8 | Int(inbound[inbound.index(offset, offsetBy: i)])
                }
                length = value
                inbound.formIndex(&offset, offsetBy: 8)
            }
            var maskKey: [UInt8]?
            if masked {
                guard inbound.distance(from: offset, to: inbound.endIndex) >= 4 else { return }
                let keyStart = offset
                maskKey = (0..<4).map { inbound[inbound.index(keyStart, offsetBy: $0)] }
                inbound.formIndex(&offset, offsetBy: 4)
            }
            guard inbound.distance(from: offset, to: inbound.endIndex) >= length else { return }
            var payload = inbound.subdata(in: offset..<inbound.index(offset, offsetBy: length))
            inbound.removeSubrange(..<inbound.index(offset, offsetBy: length))
            if let maskKey {
                for i in 0..<payload.count {
                    payload[i] ^= maskKey[i % 4]
                }
            }

            switch opcode {
            case .ping:
                let pong = Self.frame(opcode: .pong, payload: payload, masked: true)
                connection.send(content: pong, contentContext: .defaultMessage, isComplete: true, completion: .contentProcessed { _ in })
            case .pong:
                break // liveness only
            case .close:
                let echo = Self.frame(opcode: .close, payload: payload, masked: true)
                connection.send(content: echo, contentContext: .defaultMessage, isComplete: true, completion: .contentProcessed { [weak self] _ in
                    self?.connection.cancel()
                })
                finish(nil)
                emitEvent(.closed)
                return
            case .text, .binary, .continuation:
                guard fin else {
                    fragmentedPayload.append(payload)
                    fragmentedText = (opcode == .text) || fragmentedText
                    continue
                }
                var message = fragmentedPayload
                message.append(payload)
                let isText = (opcode == .text) || fragmentedText
                fragmentedPayload.removeAll(keepingCapacity: true)
                fragmentedText = false
                deliver(message: message, isText: isText)
            }
        }
    }

    private var fragmentedPayload = Data()
    private var fragmentedText = false

    private func deliver(message: Data, isText: Bool) {
        let waiter: CheckedContinuation<Data?, Error>? = lock.withLock {
            if terminal != nil { return nil }
            if waiters.isEmpty {
                frames.append(message)
                return nil
            }
            return waiters.removeFirst()
        }
        waiter?.resume(returning: message)
        _ = isText // BSATN rides binary frames; text is tolerated, not typed
    }

    /// One complete frame, client-masked when `masked` (server-bound).
    private static func frame(opcode: Opcode, payload: Data, masked: Bool) -> Data {
        var frame = Data()
        frame.append(0x80 | opcode.rawValue) // FIN + opcode
        let length = payload.count
        var maskKey: [UInt8] = []
        if masked {
            maskKey = (0..<4).map { _ in UInt8.random(in: 0...255) }
        }
        func appendLength(_ value: Int) {
            if value < 126 {
                frame.append(UInt8(value) | (masked ? 0x80 : 0))
            } else if value <= 0xFFFF {
                frame.append(126 | (masked ? 0x80 : 0))
                frame.append(UInt8(value >> 8))
                frame.append(UInt8(value & 0xFF))
            } else {
                frame.append(127 | (masked ? 0x80 : 0))
                for shift in stride(from: 56, through: 0, by: -8) {
                    frame.append(UInt8((value >> shift) & 0xFF))
                }
            }
        }
        appendLength(length)
        if masked {
            frame.append(contentsOf: maskKey)
            for (i, byte) in payload.enumerated() {
                frame.append(byte ^ maskKey[i % 4])
            }
        } else {
            frame.append(payload)
        }
        return frame
    }

    // MARK: - Internals

    private func sendRaw(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(
                content: data,
                contentContext: .defaultMessage,
                isComplete: true,
                completion: .contentProcessed { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            )
        }
    }

    private var isTerminal: Bool {
        lock.withLock { terminal != nil }
    }

    private func fail(_ error: TransportError) {
        debugLog(">>> websocket transport failed: \(String(describing: error))")
        finish(error)
        emitEvent(.failed(String(describing: error)))
    }

    private func emitEvent(_ event: Event) {
        let handler = lock.withLock { eventHandler }
        handler?(event)
    }

    /// Terminal transition; flushes waiters. `error` nil means clean close.
    private func finish(_ error: TransportError?) {
        let flushed: [CheckedContinuation<Data?, Error>] = lock.withLock {
            guard terminal == nil else { return [] }
            terminal = .some(error)
            let pending = waiters
            waiters.removeAll()
            return pending
        }
        for continuation in flushed {
            if let error {
                continuation.resume(throwing: error)
            } else {
                continuation.resume(returning: nil)
            }
        }
    }
}
