import Foundation

public struct PointValue: Codable, Sendable, Equatable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct SizeValue: Codable, Sendable, Equatable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public struct RectValue: Codable, Sendable, Equatable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var center: PointValue {
        PointValue(x: x + (width / 2.0), y: y + (height / 2.0))
    }
}

public struct DisplayInfo: Codable, Sendable {
    public let displayID: UInt32
    public let bounds: RectValue
    public let isMain: Bool

    public init(displayID: UInt32, bounds: RectValue, isMain: Bool) {
        self.displayID = displayID
        self.bounds = bounds
        self.isMain = isMain
    }
}

public struct PermissionSnapshot: Codable, Sendable {
    public let accessibilityGranted: Bool
    public let screenRecordingGranted: Bool

    public init(accessibilityGranted: Bool, screenRecordingGranted: Bool) {
        self.accessibilityGranted = accessibilityGranted
        self.screenRecordingGranted = screenRecordingGranted
    }
}

public struct SnapshotTransform: Codable, Sendable {
    public let displayID: UInt32
    public let displayBounds: RectValue
    public let imageSize: SizeValue

    public init(displayID: UInt32, displayBounds: RectValue, imageSize: SizeValue) {
        self.displayID = displayID
        self.displayBounds = displayBounds
        self.imageSize = imageSize
    }

    public func imageToDisplay(point: PointValue) -> PointValue {
        let x = displayBounds.x + ((point.x / imageSize.width) * displayBounds.width)
        let y = displayBounds.y + ((point.y / imageSize.height) * displayBounds.height)
        return PointValue(x: x, y: y)
    }
}

public struct Snapshot: Codable, Sendable {
    public let id: String
    public let createdAt: String
    public let imageBase64PNG: String
    public let imageSize: SizeValue
    public let displayBounds: RectValue
    public let displayID: UInt32
    public let debugImagePath: String
    public let transform: SnapshotTransform

    public init(
        id: String,
        createdAt: String,
        imageBase64PNG: String,
        imageSize: SizeValue,
        displayBounds: RectValue,
        displayID: UInt32,
        debugImagePath: String,
        transform: SnapshotTransform
    ) {
        self.id = id
        self.createdAt = createdAt
        self.imageBase64PNG = imageBase64PNG
        self.imageSize = imageSize
        self.displayBounds = displayBounds
        self.displayID = displayID
        self.debugImagePath = debugImagePath
        self.transform = transform
    }
}

public struct AppInfo: Codable, Sendable {
    public let localizedName: String
    public let bundleIdentifier: String?
    public let processIdentifier: Int32
    public let isActive: Bool

    public init(localizedName: String, bundleIdentifier: String?, processIdentifier: Int32, isActive: Bool) {
        self.localizedName = localizedName
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
        self.isActive = isActive
    }
}

public struct WindowInfo: Codable, Sendable {
    public let windowID: Int
    public let ownerName: String
    public let ownerPID: Int32
    public let title: String?
    public let bounds: RectValue
    public let layer: Int

    public init(windowID: Int, ownerName: String, ownerPID: Int32, title: String?, bounds: RectValue, layer: Int) {
        self.windowID = windowID
        self.ownerName = ownerName
        self.ownerPID = ownerPID
        self.title = title
        self.bounds = bounds
        self.layer = layer
    }
}

public struct UINode: Codable, Sendable {
    public let id: String
    public let role: String?
    public let subrole: String?
    public let title: String?
    public let label: String?
    public let value: String?
    public let nodeDescription: String?
    public let frame: RectValue?
    public let actions: [String]
    public let children: [UINode]

    public init(
        id: String,
        role: String?,
        subrole: String?,
        title: String?,
        label: String?,
        value: String?,
        nodeDescription: String?,
        frame: RectValue?,
        actions: [String],
        children: [UINode]
    ) {
        self.id = id
        self.role = role
        self.subrole = subrole
        self.title = title
        self.label = label
        self.value = value
        self.nodeDescription = nodeDescription
        self.frame = frame
        self.actions = actions
        self.children = children
    }
}

public struct UIQueryResult: Codable, Sendable {
    public let snapshot: Snapshot
    public let app: AppInfo?
    public let nodes: [UINode]

    public init(snapshot: Snapshot, app: AppInfo?, nodes: [UINode]) {
        self.snapshot = snapshot
        self.app = app
        self.nodes = nodes
    }
}

public struct UIQueryResultWithOCR: Codable, Sendable {
    public let snapshot: Snapshot
    public let app: AppInfo?
    public let nodes: [UINode]
    public let ocrResult: OCRResult?
    public let axTreeWeak: Bool

    public init(snapshot: Snapshot, app: AppInfo?, nodes: [UINode], ocrResult: OCRResult?, axTreeWeak: Bool) {
        self.snapshot = snapshot
        self.app = app
        self.nodes = nodes
        self.ocrResult = ocrResult
        self.axTreeWeak = axTreeWeak
    }
}

public struct ActionResult: Codable, Sendable {
    public let ok: Bool
    public let message: String
    public let snapshot: Snapshot?

    public init(ok: Bool, message: String, snapshot: Snapshot? = nil) {
        self.ok = ok
        self.message = message
        self.snapshot = snapshot
    }
}

public enum AutomationError: LocalizedError {
    case permissionDenied(String)
    case unavailable(String)
    case invalidArgument(String)
    case notFound(String)
    case operationFailed(String)
    case staleReference(String)

    public var errorDescription: String? {
        switch self {
        case let .permissionDenied(message),
             let .unavailable(message),
             let .invalidArgument(message),
             let .notFound(message),
             let .operationFailed(message),
             let .staleReference(message):
            return message
        }
    }
}

enum DateFormats {
    static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
