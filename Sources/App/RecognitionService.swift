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
        guard image.width > 0 && image.height > 0 else { return }
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

    // MARK: - QR Code Recognition

    /// Detects and decodes QR codes in the provided CGImage using Apple Vision.
    public func recognizeQRCodes(in image: CGImage) throws -> [RecognitionItem] {
        guard image.width > 0 && image.height > 0 else { return [] }
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]

        try performRequests([request], on: image)

        guard let results = request.results else {
            return []
        }

        var seen = Set<String>()
        var items: [RecognitionItem] = []
        for observation in results {
            guard observation.symbology == .qr,
                  let payload = observation.payloadStringValue,
                  !payload.isEmpty else {
                continue
            }
            if seen.insert(payload).inserted {
                items.append(RecognitionItem(
                    type: .qrCode,
                    payload: payload,
                    confidence: observation.confidence,
                    symbology: "QR"
                ))
            }
        }
        return items
    }

    /// Asynchronously detects and decodes QR codes on a background queue.
    public func recognizeQRCodesAsync(
        in image: CGImage,
        completion: @escaping (Result<[RecognitionItem], Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                let items = try self.recognizeQRCodes(in: image)
                DispatchQueue.main.async {
                    completion(.success(items))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    // MARK: - 1D Barcode Recognition

    public static let oneDimensionalBarcodeSymbologies: [VNBarcodeSymbology] = [
        .code128,
        .code39,
        .code39Checksum,
        .code39FullASCII,
        .code39FullASCIIChecksum,
        .code93,
        .code93i,
        .ean13,
        .ean8,
        .upce,
        .codabar,
        .i2of5,
        .i2of5Checksum,
        .itf14
    ]

    /// Detects and decodes 1D barcodes in the provided CGImage using Apple Vision.
    public func recognizeBarcodes(in image: CGImage) throws -> [RecognitionItem] {
        guard image.width > 0 && image.height > 0 else { return [] }
        let request = VNDetectBarcodesRequest()
        request.symbologies = RecognitionService.oneDimensionalBarcodeSymbologies

        try performRequests([request], on: image)

        guard let results = request.results else {
            return []
        }

        var seen = Set<String>()
        var items: [RecognitionItem] = []
        for observation in results {
            guard observation.symbology != .qr,
                  observation.symbology != .microQR,
                  let payload = observation.payloadStringValue,
                  !payload.isEmpty else {
                continue
            }
            let key = "\(observation.symbology.rawValue):\(payload)"
            if seen.insert(key).inserted {
                let symbologyName = friendlySymbologyName(for: observation.symbology)
                items.append(RecognitionItem(
                    type: .barcode,
                    payload: payload,
                    confidence: observation.confidence,
                    symbology: symbologyName
                ))
            }
        }
        return items
    }

    /// Maps a Vision barcode symbology to a user-friendly display string.
    public func friendlySymbologyName(for symbology: VNBarcodeSymbology) -> String {
        switch symbology {
        case .code128: return "Code 128"
        case .code39, .code39Checksum, .code39FullASCII, .code39FullASCIIChecksum: return "Code 39"
        case .code93, .code93i: return "Code 93"
        case .ean13: return "EAN-13"
        case .ean8: return "EAN-8"
        case .upce: return "UPC-E"
        case .codabar: return "Codabar"
        case .i2of5, .i2of5Checksum: return "Interleaved 2 of 5"
        case .itf14: return "ITF-14"
        case .qr: return "QR"
        default: return symbology.rawValue
        }
    }

    /// Asynchronously detects and decodes 1D barcodes on a background queue.
    public func recognizeBarcodesAsync(
        in image: CGImage,
        completion: @escaping (Result<[RecognitionItem], Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                let items = try self.recognizeBarcodes(in: image)
                DispatchQueue.main.async {
                    completion(.success(items))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    // MARK: - OCR Text Recognition

    public static let defaultOCRLanguages: [String] = ["en-US", "pl-PL"]

    /// Extracts recognized text from a CGImage, prioritizing English and Polish.
    public func recognizeText(
        in image: CGImage,
        languages: [String] = RecognitionService.defaultOCRLanguages
    ) throws -> [RecognitionItem] {
        guard image.width > 0 && image.height > 0 else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = languages
        request.usesLanguageCorrection = true

        try performRequests([request], on: image)

        guard let results = request.results else {
            return []
        }

        var items: [RecognitionItem] = []
        for observation in results {
            guard let topCandidate = observation.topCandidates(1).first,
                  !topCandidate.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            items.append(RecognitionItem(
                type: .text,
                payload: topCandidate.string,
                confidence: topCandidate.confidence,
                symbology: nil
            ))
        }
        return items
    }

    /// Asynchronously extracts recognized text from a CGImage on a background queue.
    public func recognizeTextAsync(
        in image: CGImage,
        languages: [String] = RecognitionService.defaultOCRLanguages,
        completion: @escaping (Result<[RecognitionItem], Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                let items = try self.recognizeText(in: image, languages: languages)
                DispatchQueue.main.async {
                    completion(.success(items))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    // MARK: - Unified Recognition Action

    /// Inspects the image and automatically picks the appropriate recognition mode:
    /// Prioritizes QR Codes, then 1D Barcodes, and falls back to OCR Text extraction.
    public func recognizeUnified(in image: CGImage) throws -> RecognitionItem? {
        // 1. Try QR Code Recognition
        let qrCodes = try recognizeQRCodes(in: image)
        if let topQR = qrCodes.first {
            return topQR
        }

        // 2. Try 1D Barcode Recognition
        let barcodes = try recognizeBarcodes(in: image)
        if let topBarcode = barcodes.first {
            return topBarcode
        }

        // 3. Fallback to OCR Text Extraction
        let textItems = try recognizeText(in: image)
        if !textItems.isEmpty {
            let combinedText = textItems.map { $0.payload }.joined(separator: "\n")
            let avgConfidence = textItems.reduce(0.0) { $0 + $1.confidence } / Float(textItems.count)
            return RecognitionItem(
                type: .text,
                payload: combinedText,
                confidence: avgConfidence,
                symbology: nil
            )
        }

        return nil
    }

    /// Asynchronously runs unified recognition on a background queue.
    public func recognizeUnifiedAsync(
        in image: CGImage,
        completion: @escaping (Result<RecognitionItem?, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                let item = try self.recognizeUnified(in: image)
                DispatchQueue.main.async {
                    completion(.success(item))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    /// Copies a recognized item payload to the system pasteboard.
    @discardableResult
    public func copyPayloadToPasteboard(_ item: RecognitionItem) -> Bool {
        let pb = NSPasteboard.general
        pb.clearContents()
        return pb.setString(item.payload, forType: .string)
    }
}
