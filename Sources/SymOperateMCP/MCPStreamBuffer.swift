import Foundation
import SymOperateCore

// MARK: - Read helpers

/// Buffered reader for MCP stdin framing.
///
/// Reads from the underlying file handle in 4096-byte chunks into a shared
/// buffer and serves newline-delimited lines and Content-Length bodies from
/// it, carrying any remainder across calls. This replaces the previous
/// byte-by-byte `read(upToCount: 1)` loop, which cost O(n) syscalls per
/// message (#86). The 50 MB size guard is enforced while scanning, so an
/// oversized line is rejected without buffering it in full.
struct MCPStreamBuffer {
    /// Maximum allowed MCP message size (50 MB) to prevent unbounded memory allocation.
    static let maxMessageSize = 50 * 1024 * 1024

    /// Read chunk size: 4096 bytes keeps syscalls at O(n / 4096) per message.
    static let readChunkSize = 4096

    /// Bytes already read from the handle but not yet consumed by a caller.
    private(set) var pending = Data()

    /// Per-instance line/body limit; defaults to `maxMessageSize` and is
    /// injectable so tests can exercise the guard with small fixtures.
    private let maxLineSize: Int

    init(maxLineSize: Int = MCPStreamBuffer.maxMessageSize) {
        self.maxLineSize = maxLineSize
    }

    /// Read one MCP message from the handle.
    ///
    /// Accepts both standard MCP newline-delimited framing (one JSON object
    /// per line) and legacy LSP Content-Length framing for backward
    /// compatibility with hosts that cannot be reconfigured.
    mutating func readMessage(from handle: FileHandle) throws -> Data? {
        let data = try readLine(from: handle)
        guard let data else { return nil }
        guard !data.isEmpty else { return nil }

        // Detect Content-Length framing by peeking for the header prefix.
        if data.count >= 15,
           let prefix = String(data: data[0..<15], encoding: .utf8),
           prefix.lowercased().hasPrefix("content-length:") {
            return try readContentLengthMessage(from: handle, headerLine: data)
        }

        // Newline-delimited: the entire line is the JSON message.
        guard data.count <= maxLineSize else {
            throw AutomationError.operationFailed(
                "MCP message size \(data.count) exceeds maximum allowed size of \(maxLineSize) bytes."
            )
        }
        return data
    }

    /// Read one line (terminated by 0x0A, excluded from the result) from the
    /// handle. Returns nil only at EOF with an empty buffer; a final line
    /// without a trailing newline is still delivered. The size guard is
    /// enforced while scanning so an oversized line throws instead of letting
    /// the buffer grow without bound.
    mutating func readLine(from handle: FileHandle) throws -> Data? {
        while true {
            if let newlineIndex = pending.firstIndex(of: 0x0A) {
                let line = Data(pending[..<newlineIndex])
                pending.removeSubrange(...newlineIndex)
                return line
            }
            if pending.count > maxLineSize {
                throw AutomationError.operationFailed(
                    "MCP message size \(pending.count) exceeds maximum allowed size of \(maxLineSize) bytes."
                )
            }
            guard let chunk = try handle.read(upToCount: Self.readChunkSize), !chunk.isEmpty else {
                // EOF: deliver the remaining bytes, or nil when nothing is left.
                let line = pending
                pending.removeAll(keepingCapacity: false)
                return line.isEmpty ? nil : line
            }
            pending.append(chunk)
        }
    }

    /// Parse a Content-Length-framed message and return its body.
    /// The header line has already been read into `headerLine`.
    mutating func readContentLengthMessage(from handle: FileHandle, headerLine: Data) throws -> Data? {
        guard let headerString = String(data: headerLine, encoding: .utf8) else {
            throw AutomationError.operationFailed("Failed to decode MCP header.")
        }
        let headerTrimmed = headerString.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = headerTrimmed.components(separatedBy: ":")
        guard parts.count >= 2, parts[0].lowercased() == "content-length" else {
            throw AutomationError.operationFailed("Missing Content-Length header.")
        }
        let value = parts[1..<parts.count].joined(separator: ":").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let length = Int(value) else {
            throw AutomationError.operationFailed("Invalid Content-Length header.")
        }
        guard length <= maxLineSize else {
            throw AutomationError.operationFailed(
                "MCP message size \(length) exceeds maximum allowed size of \(maxLineSize) bytes."
            )
        }
        // Consume the blank line after the header (buffer first, then handle).
        discard(upToCount: 2, from: handle) // \r\n
        return try readBytes(from: handle, count: length)
    }

    /// Read exactly `count` bytes, serving from the buffer first and only
    /// falling back to the handle when the buffer is exhausted.
    mutating func readBytes(from handle: FileHandle, count: Int) throws -> Data {
        var data = Data()
        while data.count < count {
            let remaining = count - data.count
            if pending.isEmpty {
                guard let chunk = try handle.read(upToCount: remaining), !chunk.isEmpty else {
                    throw AutomationError.operationFailed("Unexpected end of input while reading MCP payload.")
                }
                data.append(chunk)
            } else {
                let take = min(remaining, pending.count)
                data.append(pending.prefix(take))
                pending.removeFirst(take)
            }
        }
        return data
    }

    /// Consume up to `limit` bytes from the buffer first, then the handle.
    private mutating func discard(upToCount limit: Int, from handle: FileHandle) {
        var remaining = limit
        if !pending.isEmpty {
            let take = min(remaining, pending.count)
            pending.removeFirst(take)
            remaining -= take
        }
        if remaining > 0 {
            _ = try? handle.read(upToCount: remaining)
        }
    }
}
