import AppKit
import CoreGraphics
import Foundation
import Vision

public struct OCRTextRegion: Codable, Sendable {
    public let text: String
    public let frame: RectValue
    public let confidence: Float

    public init(text: String, frame: RectValue, confidence: Float) {
        self.text = text
        self.frame = frame
        self.confidence = confidence
    }
}

public struct OCRResult: Codable, Sendable {
    public let regions: [OCRTextRegion]
    public let fullText: String

    public init(regions: [OCRTextRegion], fullText: String) {
        self.regions = regions
        self.fullText = fullText
    }
}

public struct OCRService: OCRServiceProtocol {
    public init() {}

    public func recognizeText(in image: CGImage) -> OCRResult {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return OCRResult(regions: [], fullText: "")
        }

        guard let observations = request.results else {
            return OCRResult(regions: [], fullText: "")
        }

        var regions: [OCRTextRegion] = []
        var fullTextParts: [String] = []

        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let text = candidate.string
            let confidence = candidate.confidence

            let boundingBox = observation.boundingBox
            let pixelWidth = Double(image.width)
            let pixelHeight = Double(image.height)

            let x = boundingBox.origin.x * pixelWidth
            let y = (1.0 - boundingBox.origin.y - boundingBox.height) * pixelHeight
            let width = boundingBox.width * pixelWidth
            let height = boundingBox.height * pixelHeight

            let frame = RectValue(x: x, y: y, width: width, height: height)
            regions.append(OCRTextRegion(text: text, frame: frame, confidence: confidence))
            fullTextParts.append(text)
        }

        return OCRResult(regions: regions, fullText: fullTextParts.joined(separator: "\n"))
    }

    public func isAXTreeWeak(nodeCount: Int, threshold: Int = 3) -> Bool {
        nodeCount <= threshold
    }
}
