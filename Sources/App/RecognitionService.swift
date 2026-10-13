import Cocoa
import Vision

public enum RecognitionPayloadType: String, Equatable {
    case qrCode = "QR Code"
    case barcode = "Barcode"
    case text = "Text"
}

public struct RecognitionItem: Equatable {
    public let type: RecognitionPayloadType
    public let payload: String
    public let confidence: Float
    public let symbology: String?

    public init(type: RecognitionPayloadType, payload: String, confidence: Float = 1.0, symbology: String? = nil) {
        self.type = type
        self.payload = payload
        self.confidence = confidence
        self.symbology = symbology
    }
}

public final class RecognitionService {
    public static let shared = RecognitionService()

    public init() {}

    // MARK: - Native Recognition Framework Infrastructure

    /// Checks if Apple's Vision framework requests are natively supported on this macOS platform.
    public var isVisionSupported: Bool {
        if #available(macOS 12.0, *) {
            return true
        } else {
            return false
        }
    }

    /// Creates and executes a generic Vision image request handler on a CGImage.
    public func performRequests(_ requests: [VNRequest], on image: CGImage, orientation: CGImagePropertyOrientation = .up) throws {
        let handler = VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:])
        try handler.perform(requests)
    }

    /// Asynchronously executes Vision requests on a background thread.
    public func performRequestsAsync(
        _ requests: [VNRequest],
        on image: CGImage,
        orientation: CGImagePropertyOrientation = .up,
        completion: @escaping (Result<[VNRequest], Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                try self.performRequests(requests, on: image, orientation: orientation)
                DispatchQueue.main.async {
                    completion(.success(requests))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
}
