import AppKit
import ServiceManagement
import SumKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var lastResult: ParseResult?
    private var busy = false

    private let hotKeyDefaultsKey = "hotKeyPresetIndex"
    private let absoluteSumDefaultsKey = "useAbsoluteSum"

    /// Domyślnie sumujemy ze znakami (wpływy minus wydatki).
    /// Wartości bezwzględne można włączyć w menu.
    private var useAbsoluteSum: Bool {
        UserDefaults.standard.bool(forKey: absoluteSumDefaultsKey)
    }

    private func total(of result: ParseResult) -> Decimal {
        useAbsoluteSum ? result.absoluteSum : result.sum
    }

    // MARK: - Cykl życia

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        setUpHotKey()

        HUD.shared.onClick = { [weak self] in self?.copySum() }

        let permission = Capture.hasPermission()
        Log.write("start; uprawnienie nagrywania ekranu: \(permission ? "TAK" : "NIE")")
        if !permission {
            Capture.requestPermission()
        }

        DispatchQueue.global(qos: .utility).async { OCR.warmUp() }
    }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "sum", accessibilityDescription: "SumSnap")
                ?? NSImage(systemSymbolName: "plus.forwardslash.minus", accessibilityDescription: "SumSnap")
            button.image?.isTemplate = true
        }
        rebuildMenu()
    }

    private func setUpHotKey() {
        HotKeyManager.shared.onFire = { [weak self] in
            MainActor.assumeIsolated { self?.capture() }
        }

        let index = min(UserDefaults.standard.integer(forKey: hotKeyDefaultsKey), HotKeyManager.presets.count - 1)
        if !HotKeyManager.shared.register(HotKeyManager.presets[index]) {
            HUD.shared.show(.init(
                title: "Skrót zajęty",
                subtitle: "\(HotKeyManager.presets[index].label) używa już inna aplikacja. Wybierz inny w menu 🧮.",
                symbol: "exclamationmark.triangle.fill",
                tint: .systemOrange,
                duration: 6
            ))
        }
        rebuildMenu()
    }

    // MARK: - Główny przepływ

    @objc private func capture() {
        guard !busy else { return }
        busy = true

        // Świadomie NIE blokujemy tu na `hasPermission()` — przy podpisie bez
        // profilu potrafi zwrócić false mimo nadanej zgody. Próbujemy zrobić
        // zrzut i dopiero po pustym wyniku sugerujemy uprawnienia.
        Log.write("skrót wciśnięty; preflight uprawnienia: \(Capture.hasPermission() ? "TAK" : "NIE")")

        // screencapture blokuje wątek do czasu zaznaczenia obszaru.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let image = try Capture.interactiveRegion()
                Log.write("zrzut: \(image.width)×\(image.height) px")
                let lines = try OCR.recognizeLines(in: image)
                Log.write("OCR: \(lines.count) linii: \(lines.joined(separator: " | "))")
                let result = NumberParser.parse(lines: lines)
                Log.write("liczby: \(result.numbers.count), pominięte: \(result.skipped.count), "
                    + "suma bezwzględna: \(NumberFormat.display(result.absoluteSum)), ze znakami: \(NumberFormat.display(result.sum))")
                DispatchQueue.main.async { self?.present(result) }
            } catch CaptureError.cancelled {
                DispatchQueue.main.async { self?.busy = false }
            } catch {
                let message = (error as? CaptureError).map(Self.describe) ?? error.localizedDescription
                DispatchQueue.main.async { self?.presentError(message) }
            }
        }
    }

    private func present(_ result: ParseResult) {
        busy = false
        lastResult = result
        rebuildMenu()

        guard !result.isEmpty else {
            // Najczęstsza przyczyna to nie OCR, tylko pusty zrzut z braku uprawnienia.
            let hint = Capture.hasPermission()
                ? "Nie rozpoznałem kwot. Kliknij, aby zobaczyć, co zostało przechwycone."
                : "Zrzut jest pusty — brak zgody na Nagrywanie ekranu. Kliknij, aby otworzyć Ustawienia."
            HUD.shared.show(.init(
                title: "Brak liczb",
                subtitle: hint,
                symbol: "questionmark.circle.fill",
                tint: .systemOrange,
                duration: 6
            ))
            HUD.shared.onClick = { [weak self] in
                if Capture.hasPermission() {
                    NSWorkspace.shared.open(Capture.debugImagePath)
                } else {
                    Capture.openPrivacySettings()
                }
                HUD.shared.onClick = { self?.copySum() }
            }
            return
        }

        copySum()

        var parts = ["\(result.numbers.count) \(pluralize(result.numbers.count))"]
        if !result.skipped.isEmpty {
            parts.append("pominięto \(result.skipped.count) bez groszy")
        }
        parts.append("w schowku")

        HUD.shared.show(.init(
            title: NumberFormat.display(total(of: result)),
            subtitle: parts.joined(separator: " · "),
            plus: result.hasNegatives && result.positiveSum > 0 ? "+\(NumberFormat.display(result.positiveSum))" : nil,
            minus: result.hasNegatives && result.positiveSum > 0 ? NumberFormat.display(result.negativeSum) : nil,
            symbol: "sum",
            tint: .controlAccentColor,
            duration: 4
        ))
    }

    private func presentError(_ message: String) {
        busy = false
        HUD.shared.show(.init(
            title: "Nie udało się",
            subtitle: message,
            symbol: "xmark.circle.fill",
            tint: .systemRed,
            duration: 5
        ))
    }

    private func showPermissionHUD() {
        HUD.shared.show(.init(
            title: "Brak uprawnienia",
            subtitle: "Włącz Nagrywanie ekranu dla SumSnap — kliknij, aby otworzyć Ustawienia.",
            symbol: "lock.fill",
            tint: .systemOrange,
            duration: 6
        ))
        HUD.shared.onClick = { [weak self] in
            Capture.openPrivacySettings()
            HUD.shared.onClick = { self?.copySum() }
        }
    }

    nonisolated private static func describe(_ error: CaptureError) -> String {
        switch error {
        case .cancelled: return "Anulowano."
        case .noPermission: return "Brak uprawnienia do nagrywania ekranu."
        case .failed(let message): return message
        }
    }

    private func pluralize(_ count: Int) -> String {
        let last = count % 10
        let lastTwo = count % 100
        if count == 1 { return "liczba" }
        if (2...4).contains(last) && !(12...14).contains(lastTwo) { return "liczby" }
        return "liczb"
    }

    // MARK: - Menu

    private func rebuildMenu() {
        let menu = NSMenu()

        let shortcut = HotKeyManager.shared.current?.label ?? "—"
        let capture = NSMenuItem(title: "Zsumuj zaznaczenie  (\(shortcut))", action: #selector(self.capture), keyEquivalent: "")
        capture.target = self
        menu.addItem(capture)

        menu.addItem(.separator())

        if let result = lastResult, !result.isEmpty {
            let header = NSMenuItem(title: "Ostatni wynik: \(NumberFormat.display(total(of: result)))", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)

            let details = NSMenu()
            for number in result.numbers.prefix(50) {
                details.addItem(NSMenuItem(title: NumberFormat.display(number.value), action: nil, keyEquivalent: ""))
            }
            if result.numbers.count > 50 {
                details.addItem(NSMenuItem(title: "… i \(result.numbers.count - 50) więcej", action: nil, keyEquivalent: ""))
            }
            if !result.skipped.isEmpty {
                details.addItem(.separator())
                let skipped = NSMenuItem(title: "Pominięte (bez groszy)", action: nil, keyEquivalent: "")
                skipped.isEnabled = false
                details.addItem(skipped)
                for number in result.skipped.prefix(20) {
                    details.addItem(NSMenuItem(title: number.raw, action: nil, keyEquivalent: ""))
                }
            }
            let detailsItem = NSMenuItem(title: "Rozpoznane liczby", action: nil, keyEquivalent: "")
            detailsItem.submenu = details
            menu.addItem(detailsItem)

            let copy = NSMenuItem(title: "Kopiuj sumę", action: #selector(copySum), keyEquivalent: "c")
            copy.target = self
            menu.addItem(copy)

            let copyAll = NSMenuItem(title: "Kopiuj wszystkie liczby", action: #selector(copyAll), keyEquivalent: "")
            copyAll.target = self
            menu.addItem(copyAll)

            menu.addItem(.separator())
        }

        let sumMode = NSMenuItem(title: "Sumuj bez znaków (wartości bezwzględne)", action: #selector(toggleSumMode), keyEquivalent: "")
        sumMode.target = self
        sumMode.state = useAbsoluteSum ? .on : .off
        menu.addItem(sumMode)

        let shortcutMenu = NSMenu()
        let selected = UserDefaults.standard.integer(forKey: hotKeyDefaultsKey)
        for (index, preset) in HotKeyManager.presets.enumerated() {
            let item = NSMenuItem(title: preset.label, action: #selector(changeHotKey(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.state = index == selected ? .on : .off
            shortcutMenu.addItem(item)
        }
        let shortcutItem = NSMenuItem(title: "Skrót klawiszowy", action: nil, keyEquivalent: "")
        shortcutItem.submenu = shortcutMenu
        menu.addItem(shortcutItem)

        let login = NSMenuItem(title: "Uruchamiaj przy starcie", action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        let diagnostics = NSMenu()
        let permission = NSMenuItem(
            title: Capture.hasPermission() ? "Nagrywanie ekranu: OK" : "Nagrywanie ekranu: BRAK ZGODY",
            action: #selector(openScreenRecordingSettings),
            keyEquivalent: ""
        )
        permission.target = self
        diagnostics.addItem(permission)
        let showShot = NSMenuItem(title: "Pokaż ostatni zrzut", action: #selector(showLastCapture), keyEquivalent: "")
        showShot.target = self
        diagnostics.addItem(showShot)
        let showLog = NSMenuItem(title: "Pokaż log", action: #selector(showLog), keyEquivalent: "")
        showLog.target = self
        diagnostics.addItem(showLog)
        let diagnosticsItem = NSMenuItem(title: "Diagnostyka", action: nil, keyEquivalent: "")
        diagnosticsItem.submenu = diagnostics
        menu.addItem(diagnosticsItem)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Zakończ SumSnap", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem.menu = menu
    }

    // MARK: - Akcje menu

    @objc private func copySum() {
        guard let result = lastResult, !result.isEmpty else { return }
        setClipboard(NumberFormat.clipboard(total(of: result)))
    }

    @objc private func copyAll() {
        guard let result = lastResult, !result.isEmpty else { return }
        setClipboard(result.numbers.map { NumberFormat.clipboard($0.value) }.joined(separator: "\n"))
    }

    private func setClipboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    @objc private func toggleSumMode() {
        UserDefaults.standard.set(!useAbsoluteSum, forKey: absoluteSumDefaultsKey)
        rebuildMenu()
        if let result = lastResult, !result.isEmpty {
            copySum()
            HUD.shared.show(.init(
                title: NumberFormat.display(total(of: result)),
                subtitle: useAbsoluteSum ? "bez znaków · w schowku" : "ze znakami · w schowku",
                symbol: "sum",
                tint: .controlAccentColor,
                duration: 3
            ))
        }
    }

    @objc private func openScreenRecordingSettings() {
        Capture.openPrivacySettings()
    }

    @objc private func showLastCapture() {
        guard FileManager.default.fileExists(atPath: Capture.debugImagePath.path) else {
            presentError("Nie ma jeszcze żadnego zrzutu.")
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([Capture.debugImagePath])
    }

    @objc private func showLog() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: Log.path())])
    }

    @objc private func changeHotKey(_ sender: NSMenuItem) {
        let preset = HotKeyManager.presets[sender.tag]
        guard HotKeyManager.shared.register(preset) else {
            HUD.shared.show(.init(
                title: "Skrót zajęty",
                subtitle: "\(preset.label) używa już inna aplikacja.",
                symbol: "exclamationmark.triangle.fill",
                tint: .systemOrange,
                duration: 4
            ))
            return
        }
        UserDefaults.standard.set(sender.tag, forKey: hotKeyDefaultsKey)
        rebuildMenu()
    }

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            presentError("Nie udało się zmienić ustawień startu: \(error.localizedDescription)")
        }
        rebuildMenu()
    }
}

/// Tryb diagnostyczny: `SumSnap --file zrzut.png` — wypisuje rozpoznany tekst,
/// znalezione liczby i sumę. Przydatne, gdy OCR czegoś nie łapie.
func runFileMode(path: String) -> Int32 {
    let url = URL(fileURLWithPath: path)
    guard
        let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
        FileHandle.standardError.write(Data("Nie mogę otworzyć obrazu: \(path)\n".utf8))
        return 1
    }
    do {
        let lines = try OCR.recognizeLines(in: image)
        print("— Rozpoznany tekst —")
        lines.forEach { print("  \($0)") }

        let result = NumberParser.parse(lines: lines)
        print("— Liczby (\(result.numbers.count)) —")
        result.numbers.forEach { print("  \(NumberFormat.display($0.value))   ← \"\($0.raw)\"") }
        if !result.skipped.isEmpty {
            print("— Pominięte (\(result.skipped.count)) —")
            result.skipped.forEach { print("  \($0.raw)") }
        }
        print("— Suma —")
        print("  \(NumberFormat.display(result.sum))")
        return 0
    } catch {
        FileHandle.standardError.write(Data("Błąd OCR: \(error.localizedDescription)\n".utf8))
        return 1
    }
}

if let index = CommandLine.arguments.firstIndex(of: "--file"), index + 1 < CommandLine.arguments.count {
    exit(runFileMode(path: CommandLine.arguments[index + 1]))
}

/// Jak `--file`, ale z uruchomioną pętlą aplikacji i OCR-em na wątku tła —
/// czyli w warunkach identycznych z tymi po naciśnięciu skrótu.
if let index = CommandLine.arguments.firstIndex(of: "--selftest"), index + 1 < CommandLine.arguments.count {
    let path = CommandLine.arguments[index + 1]
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            DispatchQueue.global(qos: .userInitiated).async {
                let code = runFileMode(path: path)
                exit(code)
            }
        }
        app.run()
    }
}

// Kod najwyższego poziomu wykonuje się na wątku głównym, ale kompilator o tym nie wie.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory) // tylko ikona w pasku menu, bez Docka
    objc_setAssociatedObject(app, "SumSnapDelegate", delegate, .OBJC_ASSOCIATION_RETAIN)
    app.run()
}
