import CoreGraphics
import Foundation
import ImageIO
import Vision
import WatakeDomain

/// Apple Vision implementation of the private OCR boundary. Vision request
/// objects exist only inside this type's detached processing work.
public struct VisionOCRRecognizer: OCRRecognizing {
    public init() {}

    public func recognize(imageData: Data, configuration: OCRConfiguration = OCRConfiguration()) async throws -> OCRRecognitionResult {
        try Task.checkCancellation()
        let completion = VisionRecognitionCompletion()
        let work = Task.detached(priority: .userInitiated) {
            do {
                try Task.checkCancellation()
                let result = try VisionOCRRecognizer.performRecognition(imageData: imageData, configuration: configuration)
                await completion.finish(.success(result))
            } catch is CancellationError {
                await completion.finish(.cancelled)
            } catch let error as OCRRecognitionError {
                await completion.finish(.failure(error))
            } catch {
                await completion.finish(.failure(.requestFailed))
            }
        }
        return try await withTaskCancellationHandler {
            try await completion.value()
        } onCancel: {
            // Legacy VNImageRequestHandler has no cancellation API. Cancelling
            // the worker propagates intent; completing the caller immediately
            // prevents a synchronous handler from delaying viewer cancellation.
            work.cancel()
            Task { await completion.cancel() }
        }
    }

    private static func performRecognition(imageData: Data, configuration: OCRConfiguration) throws -> OCRRecognitionResult {
        guard let orientation = imageOrientation(for: imageData) else {
            throw OCRRecognitionError.imageUnreadable
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        if !configuration.preferredLanguages.isEmpty {
            request.recognitionLanguages = configuration.preferredLanguages
        }

        let handler = VNImageRequestHandler(data: imageData, orientation: orientation)
        do {
            try handler.perform([request])
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw OCRRecognitionError.requestFailed
        }
        try Task.checkCancellation()

        let blocks: [OCRBlock] = (request.results ?? []).compactMap { observation -> OCRBlock? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            guard let bounds = OCRVisionGeometry.topLeftNormalizedRect(from: observation.boundingBox) else { return nil }
            return OCRBlock(
                id: UUID(),
                text: candidate.string,
                confidence: Double(candidate.confidence),
                bounds: bounds
            )
        }
        let result = OCRRecognitionResult(
            text: blocks.map(\.text).joined(separator: "\n"),
            blocks: blocks
        )
        do {
            try result.validate()
        } catch {
            throw OCRRecognitionError.invalidResult
        }
        return result
    }

    private static func imageOrientation(for data: Data) -> CGImagePropertyOrientation? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let rawValue = properties?[kCGImagePropertyOrientation] as? UInt32 ?? 1
        return CGImagePropertyOrientation(rawValue: rawValue)
    }
}

private actor VisionRecognitionCompletion {
    enum Outcome: Sendable {
        case success(OCRRecognitionResult)
        case cancelled
        case failure(OCRRecognitionError)
    }

    private var outcome: Outcome?
    private var continuation: CheckedContinuation<OCRRecognitionResult, Error>?

    func value() async throws -> OCRRecognitionResult {
        if let outcome {
            return try resolve(outcome)
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func finish(_ outcome: Outcome) {
        guard self.outcome == nil else { return }
        self.outcome = outcome
        guard let continuation else { return }
        self.continuation = nil
        do {
            try continuation.resume(returning: resolve(outcome))
        } catch {
            continuation.resume(throwing: error)
        }
    }

    func cancel() {
        finish(.cancelled)
    }

    private func resolve(_ outcome: Outcome) throws -> OCRRecognitionResult {
        switch outcome {
        case .success(let result):
            result
        case .cancelled:
            throw CancellationError()
        case .failure(let error):
            throw error
        }
    }
}

/// Converts Vision's lower-left normalized image coordinate space to Watake's
/// top-left contract and clamps partially out-of-range framework geometry.
public enum OCRVisionGeometry {
    public static func topLeftNormalizedRect(from visionBounds: CGRect) -> WatakeDomain.NormalizedRect? {
        guard hasFinitePositiveDimensions(visionBounds) else { return nil }

        let topLeft = CGRect(
            x: visionBounds.minX,
            y: 1 - visionBounds.maxY,
            width: visionBounds.width,
            height: visionBounds.height
        )
        let clamped = topLeft.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !clamped.isNull, clamped.width > 0, clamped.height > 0 else {
            return nil
        }
        let normalized = WatakeDomain.NormalizedRect(
            originX: clamped.minX,
            originY: clamped.minY,
            width: clamped.width,
            height: clamped.height
        )
        guard (try? normalized.validateForOCR()) != nil else {
            return nil
        }
        return normalized
    }

    private static func hasFinitePositiveDimensions(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite &&
            rect.width.isFinite && rect.height.isFinite &&
            rect.width > 0 && rect.height > 0
    }
}
