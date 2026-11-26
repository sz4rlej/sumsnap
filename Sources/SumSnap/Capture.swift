import AppKit
import CoreGraphics

enum CaptureError: Error {
    case cancelled
    case noPermission
    case failed(String)
}

enum Capture {

    /// Uprawnienie "Nagrywanie ekranu" — bez niego `screencapture` zwróci pusty obraz.
    static func hasPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    static func requestPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    static func openPrivacySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    /// Uruchamia systemowe zaznaczanie obszaru (jak ⌘⇧4) i zwraca zrzut.
    /// Rzuca `.cancelled`, gdy użytkownik naciśnie Esc.
    static func interactiveRegion() throws -> CGImage {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sumsnap-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // -i: zaznaczanie myszą, -x: bez dźwięku migawki, -o: bez cienia okna
        process.arguments = ["-i", "-x", "-o", url.path]

        do {
            try process.run()
        } catch {
            throw CaptureError.failed(error.localizedDescription)
        }
        process.waitUntilExit()

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CaptureError.cancelled
        }
        saveDebugCopy(of: url)

        // Wczytujemy bajty do pamięci, a nie przez CGImageSourceCreateWithURL:
        // ten drugi czyta piksele leniwie, a plik znika w `defer` powyżej —
        // OCR dostawał wtedy pusty obraz o poprawnych wymiarach.
        guard let data = try? Data(contentsOf: url) else {
            throw CaptureError.failed("Nie udało się odczytać zrzutu ekranu.")
        }
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: true] as CFDictionary)
        else {
            throw CaptureError.failed("Nie udało się zdekodować zrzutu ekranu.")
        }
        return image
    }

    /// Ostatni zrzut zostaje na dysku — bez tego nie da się stwierdzić, czy pusty
    /// wynik to wina OCR, czy tego, że macOS oddał obraz bez zawartości okien.
    static let debugImagePath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/SumSnap-last.png")

    private static func saveDebugCopy(of url: URL) {
        try? FileManager.default.removeItem(at: debugImagePath)
        try? FileManager.default.copyItem(at: url, to: debugImagePath)
    }
}
