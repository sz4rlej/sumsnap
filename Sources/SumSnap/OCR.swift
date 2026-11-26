import CoreGraphics
import CoreText
import Foundation
import Vision

enum OCR {

    /// Rozpoznaje tekst i zwraca go liniami w kolejności od góry do dołu.
    static func recognizeLines(in image: CGImage) throws -> [String] {
        let source = upscaleIfNeeded(image)
        Log.write("OCR wejście: \(source.width)×\(source.height) px, "
            + "bity/kanał: \(source.bitsPerComponent), bity/piksel: \(source.bitsPerPixel), "
            + "profil: \(source.colorSpace?.name.map(String.init(describing:)) ?? "brak")")
        dumpOCRInput(source)

        // Konfiguracja z wymuszonymi językami bywa zawodna, gdy model dla danego
        // języka nie jest jeszcze gotowy — wtedy próbujemy ustawień domyślnych.
        if let lines = try? attempt(on: source, languages: ["pl-PL", "en-US"], label: "pl+en"), !lines.isEmpty {
            return lines
        }
        if let lines = try? attempt(on: source, languages: nil, label: "domyślne"), !lines.isEmpty {
            return lines
        }
        return try attempt(on: source, languages: ["en-US"], label: "en")
    }

    /// Zapisuje dokładnie ten obraz, który dostaje Vision — jedyny sposób, by
    /// odróżnić „OCR nie umie tego przeczytać" od „obraz dotarł pusty".
    static let ocrInputPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/SumSnap-ocr-input.png")

    private static func dumpOCRInput(_ image: CGImage) {
        guard let destination = CGImageDestinationCreateWithURL(
            ocrInputPath as CFURL, "public.png" as CFString, 1, nil
        ) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }

    private static func attempt(on image: CGImage, languages: [String]?, label: String) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Kluczowe dla kwot: korekta językowa lubi zamieniać "1 234,56" na słowa.
        request.usesLanguageCorrection = false
        if let languages { request.recognitionLanguages = languages }
        request.minimumTextHeight = 0

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            Log.write("OCR [\(label)] błąd: \(error.localizedDescription)")
            throw error
        }

        let observations = request.results ?? []
        Log.write("OCR [\(label)]: \(observations.count) obszarów tekstu")

        // Vision zwraca współrzędne z (0,0) w lewym dolnym rogu — sortujemy w kolejności czytania.
        let sorted = observations.sorted { a, b in
            let dy = a.boundingBox.midY - b.boundingBox.midY
            if abs(dy) > 0.01 { return dy > 0 }
            return a.boundingBox.minX < b.boundingBox.minX
        }

        return sorted.compactMap { $0.topCandidates(1).first?.string }
    }

    /// Pierwsze rozpoznanie w świeżym procesie potrafi zwrócić zero obszarów,
    /// zanim Vision załaduje swoje modele. Rozgrzewamy je zaraz po starcie,
    /// żeby pierwsze użycie skrótu nie trafiło w to okno.
    static func warmUp() {
        guard let image = sampleImage() else { return }
        let lines = (try? recognizeLines(in: image)) ?? []
        Log.write("rozgrzewka OCR: \(lines.isEmpty ? "pusto" : lines.joined())")
    }

    private static func sampleImage() -> CGImage? {
        let width = 240, height = 80
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }

        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(gray: 0, alpha: 1)

        // Cyfry rysowane prostokątami — wystarczą, by zmusić Vision do inicjalizacji.
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 48, nil)
        let attributed = NSAttributedString(
            string: "123,45",
            attributes: [.font: font, .foregroundColor: CGColor(gray: 0, alpha: 1)]
        )
        let line = CTLineCreateWithAttributedString(attributed)
        context.textPosition = CGPoint(x: 10, y: 20)
        CTLineDraw(line, context)

        return context.makeImage()
    }

    /// Małe zaznaczenia (np. wąska kolumna kwot) OCR-ują się wyraźnie lepiej po powiększeniu.
    private static func upscaleIfNeeded(_ image: CGImage) -> CGImage {
        let minWidth = 1200
        guard image.width < minWidth else { return image }

        let scale = max(2, Int((Double(minWidth) / Double(image.width)).rounded(.up)))
        let width = image.width * scale
        let height = image.height * scale

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return image }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }
}
