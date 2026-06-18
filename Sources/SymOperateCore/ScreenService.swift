import AppKit
import CoreGraphics
import CoreMedia
import Foundation
import ImageIO
@preconcurrency import ScreenCaptureKit

public final class ScreenService {
    private let fm = FileManager.default
    private let snapshotDirectory: URL

    public init(snapshotDirectory: URL = FileManager.default.temporaryDirectory.appendingPathComponent("symoperate-snapshots", isDirectory: true)) {
        self.snapshotDirectory = snapshotDirectory
        try? fm.createDirectory(at: snapshotDirectory, withIntermediateDirectories: true)
    }

    public func listDisplays() -> [DisplayInfo] {
        var displayCount: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &displayCount) == .success, displayCount > 0 else {
            let mainID = CGMainDisplayID()
            let mainBounds = CGDisplayBounds(mainID)
            return [DisplayInfo(displayID: mainID, bounds: RectValue(x: mainBounds.origin.x, y: mainBounds.origin.y, width: mainBounds.size.width, height: mainBounds.size.height), isMain: true)]
        }

        var ids = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        _ = CGGetActiveDisplayList(displayCount, &ids, &displayCount)

        let mainID = CGMainDisplayID()
        var seen = Set<UInt32>()
        var displays: [DisplayInfo] = []

        for id in ids {
            guard !seen.contains(id) else { continue }
            seen.insert(id)
            let bounds = CGDisplayBounds(id)
            displays.append(DisplayInfo(
                displayID: id,
                bounds: RectValue(x: bounds.origin.x, y: bounds.origin.y, width: bounds.size.width, height: bounds.size.height),
                isMain: id == mainID
            ))
        }

        return displays
    }

    public func captureMainDisplay(maxDimension: CGFloat = 1280) throws -> Snapshot {
        let id = UUID().uuidString
        let debugPath = snapshotDirectory.appendingPathComponent("\(id).png")

        let captureResult = try captureScreenWithScreenCaptureKit()

        let displayBounds = CGDisplayBounds(CGMainDisplayID())
        let scaled = resizeIfNeeded(image: captureResult.image, maxDimension: maxDimension)
        let png = try pngData(for: scaled)

        try png.write(to: debugPath)

        let imageSize = SizeValue(width: Double(scaled.width), height: Double(scaled.height))
        let bounds = RectValue(
            x: displayBounds.origin.x,
            y: displayBounds.origin.y,
            width: displayBounds.size.width,
            height: displayBounds.size.height
        )
        let transform = SnapshotTransform(displayID: CGMainDisplayID(), displayBounds: bounds, imageSize: imageSize)
        return Snapshot(
            id: id,
            createdAt: DateFormats.iso8601String(from: Date()),
            imageBase64PNG: png.base64EncodedString(),
            imageSize: imageSize,
            displayBounds: bounds,
            displayID: CGMainDisplayID(),
            debugImagePath: debugPath.path,
            transform: transform
        )
    }

    public func captureDisplay(displayID: UInt32, maxDimension: CGFloat = 1280) throws -> Snapshot {
        let id = UUID().uuidString
        let debugPath = snapshotDirectory.appendingPathComponent("\(id).png")

        let captureResult = try captureScreenWithScreenCaptureKit(displayID: displayID)

        let displayBounds = CGDisplayBounds(displayID)
        let scaled = resizeIfNeeded(image: captureResult.image, maxDimension: maxDimension)
        let png = try pngData(for: scaled)

        try png.write(to: debugPath)

        let imageSize = SizeValue(width: Double(scaled.width), height: Double(scaled.height))
        let bounds = RectValue(
            x: displayBounds.origin.x,
            y: displayBounds.origin.y,
            width: displayBounds.size.width,
            height: displayBounds.size.height
        )
        let transform = SnapshotTransform(displayID: displayID, displayBounds: bounds, imageSize: imageSize)
        return Snapshot(
            id: id,
            createdAt: DateFormats.iso8601String(from: Date()),
            imageBase64PNG: png.base64EncodedString(),
            imageSize: imageSize,
            displayBounds: bounds,
            displayID: displayID,
            debugImagePath: debugPath.path,
            transform: transform
        )
    }

    public func captureWindow(windowID: Int, maxDimension: CGFloat = 1280) throws -> Snapshot {
        let id = UUID().uuidString
        let debugPath = snapshotDirectory.appendingPathComponent("\(id).png")

        let captureResult = try captureScreenWithScreenCaptureKit(windowID: windowID)

        let windowBounds = windowBounds(for: windowID)
        let scaled = resizeIfNeeded(image: captureResult.image, maxDimension: maxDimension)
        let png = try pngData(for: scaled)

        try png.write(to: debugPath)

        let imageSize = SizeValue(width: Double(scaled.width), height: Double(scaled.height))
        let bounds = RectValue(
            x: windowBounds.origin.x,
            y: windowBounds.origin.y,
            width: windowBounds.size.width,
            height: windowBounds.size.height
        )
        let displayID = CGMainDisplayID()
        let transform = SnapshotTransform(displayID: displayID, displayBounds: bounds, imageSize: imageSize)
        return Snapshot(
            id: id,
            createdAt: DateFormats.iso8601String(from: Date()),
            imageBase64PNG: png.base64EncodedString(),
            imageSize: imageSize,
            displayBounds: bounds,
            displayID: displayID,
            debugImagePath: debugPath.path,
            transform: transform
        )
    }

    private func captureScreenWithScreenCaptureKit(displayID: CGDirectDisplayID = CGMainDisplayID()) throws -> (image: CGImage, contentRect: CGRect) {
        let box = SendableBox<CGImage?>(value: nil)
        let rectBox = SendableBox<CGRect?>(value: nil)
        let errorBox = SendableBox<Error?>(value: nil)
        let semaphore = DispatchSemaphore(value: 0)

        Task { @MainActor in
            do {
                let content = try await SCShareableContent.current

                guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                    throw AutomationError.operationFailed("Display \(displayID) not found in ScreenCaptureKit.")
                }

                let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
                let config = SCStreamConfiguration()
                config.pixelFormat = kCVPixelFormatType_32BGRA
                config.showsCursor = false

                let (image, rect) = try await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: config
                )
                box.value = image
                rectBox.value = rect
            } catch {
                errorBox.value = error
            }
            semaphore.signal()
        }

        if Thread.isMainThread {
            while semaphore.wait(timeout: .now()) == .timedOut {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
            }
        } else {
            semaphore.wait()
        }

        if let error = errorBox.value {
            let nsError = error as NSError
            if nsError.domain == "com.apple.ScreenCaptureKit" {
                if nsError.code == -3801 {
                    throw AutomationError.permissionDenied("Screen Recording permission is denied. Enable it in System Settings > Privacy & Security > Screen Recording.")
                }
            }
            throw AutomationError.operationFailed("Screen capture failed: \(error.localizedDescription)")
        }

        guard let image = box.value else {
            throw AutomationError.operationFailed("Failed to capture screen image.")
        }

        return (image, rectBox.value ?? CGRect.zero)
    }

    private func captureScreenWithScreenCaptureKit(windowID: Int) throws -> (image: CGImage, contentRect: CGRect) {
        let box = SendableBox<CGImage?>(value: nil)
        let rectBox = SendableBox<CGRect?>(value: nil)
        let errorBox = SendableBox<Error?>(value: nil)
        let semaphore = DispatchSemaphore(value: 0)

        Task { @MainActor in
            do {
                let content = try await SCShareableContent.current

                guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                    throw AutomationError.notFound("Window \(windowID) not found in ScreenCaptureKit.")
                }

                guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) else {
                    throw AutomationError.operationFailed("Main display not found for window capture.")
                }

                let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [window])
                let config = SCStreamConfiguration()
                config.pixelFormat = kCVPixelFormatType_32BGRA
                config.showsCursor = false

                let (image, rect) = try await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: config
                )
                box.value = image
                rectBox.value = rect
            } catch {
                errorBox.value = error
            }
            semaphore.signal()
        }

        if Thread.isMainThread {
            while semaphore.wait(timeout: .now()) == .timedOut {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
            }
        } else {
            semaphore.wait()
        }

        if let error = errorBox.value {
            let nsError = error as NSError
            if nsError.domain == "com.apple.ScreenCaptureKit" {
                if nsError.code == -3801 {
                    throw AutomationError.permissionDenied("Screen Recording permission is denied. Enable it in System Settings > Privacy & Security > Screen Recording.")
                }
            }
            throw AutomationError.operationFailed("Window capture failed: \(error.localizedDescription)")
        }

        guard let image = box.value else {
            throw AutomationError.operationFailed("Failed to capture window image.")
        }

        return (image, rectBox.value ?? CGRect.zero)
    }

    private func windowBounds(for windowID: Int) -> CGRect {
        guard let rawList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return .zero
        }

        for row in rawList {
            guard let wid = row[kCGWindowNumber as String] as? Int, wid == windowID,
                  let boundsDict = row[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = boundsDict["X"],
                  let y = boundsDict["Y"],
                  let width = boundsDict["Width"],
                  let height = boundsDict["Height"]
            else { continue }
            return CGRect(x: x, y: y, width: width, height: height)
        }

        return .zero
    }

    private func resizeIfNeeded(image: CGImage, maxDimension: CGFloat) -> CGImage {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let ratio = min(1.0, maxDimension / max(width, height))
        guard ratio < 0.999 else { return image }

        let targetWidth = Int((width * ratio).rounded(.toNearestOrEven))
        let targetHeight = Int((height * ratio).rounded(.toNearestOrEven))

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: targetWidth * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return image
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(targetWidth), height: CGFloat(targetHeight)))
        return context.makeImage() ?? image
    }

    private func pngData(for image: CGImage) throws -> Data {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw AutomationError.operationFailed("Failed to encode screenshot as PNG.")
        }
        return data
    }
}

private final class SendableBox<T>: @unchecked Sendable {
    var value: T
    init(value: T) {
        self.value = value
    }
}

private extension SCScreenshotManager {
    static func captureImage(
        contentFilter filter: SCContentFilter,
        configuration config: SCStreamConfiguration
    ) async throws -> (CGImage, CGRect) {
        let sampleBuffer = try await captureSampleBuffer(
            contentFilter: filter,
            configuration: config
        )

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            throw AutomationError.operationFailed("No pixel buffer in sample buffer.")
        }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        guard let cgImage = CIContext().createCGImage(
            ciImage,
            from: ciImage.extent
        ) else {
            throw AutomationError.operationFailed("Failed to create CGImage from pixel buffer.")
        }

        var contentRect = CGRect.zero
        if let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[String: Any]] {
            if let firstAttachment = attachmentsArray.first {
                if let rectDict = firstAttachment["Rect"] as? [String: CGFloat] {
                    contentRect = CGRect(
                        x: rectDict["X"] ?? 0,
                        y: rectDict["Y"] ?? 0,
                        width: rectDict["Width"] ?? 0,
                        height: rectDict["Height"] ?? 0
                    )
                }
            }
        }

        return (cgImage, contentRect)
    }
}
