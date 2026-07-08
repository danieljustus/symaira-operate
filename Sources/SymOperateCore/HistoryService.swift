import Foundation

public final class HistoryService: HistoryServiceProtocol, Sendable {
    private let fileURL: URL
    private let maxEvents = 1000

    public init(fileURL: URL? = nil) {
        if let fileURL = fileURL {
            self.fileURL = fileURL
        } else {
            let localShare = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/share/symoperate")
            try? FileManager.default.createDirectory(at: localShare, withIntermediateDirectories: true, attributes: nil)
            self.fileURL = localShare.appendingPathComponent("history.jsonl")
        }
    }

    public func record(_ event: HistoryEvent) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        
        let data = try encoder.encode(event)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            return
        }

        let line = jsonString + "\n"
        if let fileHandle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? fileHandle.close() }
            if #available(macOS 10.15.4, *) {
                try fileHandle.seekToEnd()
                try fileHandle.write(contentsOf: Data(line.utf8))
            } else {
                fileHandle.seekToEndOfFile()
                fileHandle.write(Data(line.utf8))
            }
        } else {
            try line.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    public func events() throws -> [HistoryEvent] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        let lines = contents.components(separatedBy: .newlines).filter { !$0.isEmpty }
        
        let decoder = JSONDecoder()
        var results: [HistoryEvent] = []
        for line in lines {
            if let data = line.data(using: .utf8),
               let event = try? decoder.decode(HistoryEvent.self, from: data) {
                results.append(event)
            }
        }
        
        if results.count > maxEvents {
            return Array(results.suffix(maxEvents))
        }
        return results
    }
}
