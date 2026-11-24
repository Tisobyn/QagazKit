//
//  ScannerTestViewModel.swift
//  QagazKit
//
//  Test code: drives the scanner test screen.
//

import SwiftUI
import PDFKit
import Combine

@MainActor
final class ScannerTestViewModel: ObservableObject {

    enum Step: Int, CaseIterable {
        case find, connect, scan, result

        var title: String {
            switch self {
            case .find: return "Find"
            case .connect: return "Connect"
            case .scan: return "Scan"
            case .result: return "Result"
            }
        }
    }

    enum ConnectionState: Equatable {
        case idle
        case connecting
        case connected
        case failed(String)
    }

    enum ScanState: Equatable {
        case idle
        case scanning
        case done
        case failed(String)
    }

    struct LogLine: Identifiable {
        let id = UUID()
        let time: String
        let text: String
        let isError: Bool
    }

    // Find
    @Published var scanners: [ESCLScanner] = []
    @Published var isSearching = false
    @Published var manualIP = ""

    // Connect
    @Published var selected: ESCLScanner?
    @Published var connection: ConnectionState = .idle
    @Published var capabilities: ESCLCapabilities?

    // Scan
    @Published var settings = ESCLScanSettings()
    @Published var scanState: ScanState = .idle
    @Published var pagesReceived = 0

    // Result
    @Published var pages: [ESCLPage] = []
    @Published var pdfURL: URL?
    @Published var scanDuration: TimeInterval = 0

    @Published var log: [LogLine] = []

    private let discovery = ESCLDiscovery()
    private var client: ESCLClient?
    private var scanTask: Task<Void, Never>?

    var currentStep: Step {
        if scanState == .done { return .result }
        if connection == .connected { return .scan }
        if selected != nil { return .connect }
        return .find
    }

    // MARK: - Find

    func startSearch() {
        isSearching = true
        addLog("Searching for scanners (_uscan._tcp, _uscans._tcp)...")
        discovery.onUpdate = { [weak self] list in
            guard let self else { return }
            if list.count > self.scanners.count, let last = list.last {
                self.addLog("Found: \(last.name) at \(last.host):\(last.port)")
            }
            self.scanners = list
        }
        discovery.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self, self.isSearching else { return }
            self.isSearching = false
            if self.scanners.isEmpty {
                self.addLog("No scanners found in 10 seconds.", error: true)
            }
        }
    }

    func stopSearch() {
        discovery.stop()
        isSearching = false
    }

    func addManualScanner() {
        let text = manualIP.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        let parts = text.split(separator: ":")
        let host = String(parts.first ?? "")
        let port = parts.count > 1 ? Int(parts[1]) ?? 80 : 80
        let scanner = ESCLScanner(
            id: "manual-\(text)", name: "Manual: \(host)", host: host, port: port,
            isSecure: port == 443, rootPath: "eSCL", formats: [], sources: []
        )
        scanners.removeAll { $0.id == scanner.id }
        scanners.append(scanner)
        addLog("Added manually: \(host):\(port)")
        manualIP = ""
    }

    // MARK: - Connect

    func connect(to scanner: ESCLScanner) {
        resetScanResult()
        selected = scanner
        connection = .connecting
        capabilities = nil
        client = ESCLClient(scanner: scanner)
        addLog("Connecting to \(scanner.name)...")
        Task {
            do {
                let caps = try await client!.fetchCapabilities()
                capabilities = caps
                applyDefaults(for: caps)
                connection = .connected
                addLog("Connected: \(caps.makeAndModel), eSCL \(caps.version)")
            } catch {
                connection = .failed(Self.message(for: error))
                addLog("Connect failed: \(Self.message(for: error))", error: true)
            }
        }
    }

    func disconnect() {
        scanTask?.cancel()
        client?.cancel()
        client = nil
        selected = nil
        capabilities = nil
        connection = .idle
        resetScanResult()
    }

    private func applyDefaults(for caps: ESCLCapabilities) {
        var s = ESCLScanSettings()
        s.source = caps.hasPlaten ? .platen : .feeder
        if let dpi = caps.resolutions.min(by: { abs($0 - 300) < abs($1 - 300) }) { s.dpi = dpi }
        if caps.formats.contains("image/jpeg") {
            s.format = "image/jpeg"
        } else if let first = caps.formats.first {
            s.format = first
        }
        let modes = caps.colorModes
        if !modes.isEmpty, !modes.contains(s.color.rawValue),
           let m = ESCLColorMode.allCases.first(where: { modes.contains($0.rawValue) }) {
            s.color = m
        }
        settings = s
    }

    // MARK: - Scan

    func startScan() {
        guard let client, let caps = capabilities else { return }
        resetScanResult()
        scanState = .scanning
        addLog("Scan started: \(settings.source.rawValue), \(settings.color.rawValue), \(settings.dpi) dpi, \(settings.format)")
        let started = Date()
        scanTask = Task {
            do {
                let result = try await client.scan(settings: settings, capabilities: caps) { [weak self] count in
                    Task { @MainActor in
                        self?.pagesReceived = count
                        self?.addLog("Page \(count) received")
                    }
                }
                pages = result
                scanDuration = Date().timeIntervalSince(started)
                pdfURL = makePDF(from: result)
                scanState = .done
                addLog("Done: \(result.count) page(s) in \(String(format: "%.1f", scanDuration)) s")
            } catch {
                if Task.isCancelled { return }
                scanState = .failed(Self.message(for: error))
                addLog("Scan failed: \(Self.message(for: error))", error: true)
            }
        }
    }

    func cancelScan() {
        addLog("Cancelling scan...")
        client?.cancel()
        // The old session is closed. Make a fresh client for the next scan.
        if let selected { client = ESCLClient(scanner: selected) }
        scanTask?.cancel()
        scanState = .idle
    }

    func scanAgain() {
        resetScanResult()
    }

    private func resetScanResult() {
        pages = []
        pdfURL = nil
        pagesReceived = 0
        scanState = .idle
    }

    // MARK: - Result helpers

    func image(for page: ESCLPage) -> UIImage? {
        if page.mime.contains("pdf") {
            guard let doc = PDFDocument(data: page.data), let first = doc.page(at: 0) else { return nil }
            return first.thumbnail(of: CGSize(width: 900, height: 1200), for: .mediaBox)
        }
        return UIImage(data: page.data)
    }

    var totalSizeText: String {
        let bytes = pages.reduce(0) { $0 + $1.data.count }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    var firstPageSizeText: String {
        guard let page = pages.first, let img = image(for: page) else { return "-" }
        return "\(Int(img.size.width * img.scale)) x \(Int(img.size.height * img.scale)) px"
    }

    private func makePDF(from pages: [ESCLPage]) -> URL? {
        let document = PDFDocument()
        for page in pages {
            if page.mime.contains("pdf"), let doc = PDFDocument(data: page.data) {
                for i in 0..<doc.pageCount {
                    if let p = doc.page(at: i) { document.insert(p, at: document.pageCount) }
                }
            } else if let img = UIImage(data: page.data), let pdfPage = PDFPage(image: img) {
                document.insert(pdfPage, at: document.pageCount)
            }
        }
        guard document.pageCount > 0 else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Scan-\(Int(Date().timeIntervalSince1970)).pdf")
        return document.write(to: url) ? url : nil
    }

    /// Opens the iOS print dialog (it lets the user pick a printer) for the scanned PDF.
    func printScan() {
        guard let url = pdfURL, let data = try? Data(contentsOf: url) else { return }
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = url.lastPathComponent
        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printingItem = data
        controller.present(animated: true) { [weak self] _, completed, error in
            Task { @MainActor in
                if let error {
                    self?.addLog("Print failed: \(error.localizedDescription)", error: true)
                } else if completed {
                    self?.addLog("Sent to printer")
                }
            }
        }
    }

    // MARK: - Log

    func addLog(_ text: String, error: Bool = false) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        log.append(LogLine(time: formatter.string(from: Date()), text: text, isError: error))
    }

    private static func message(for error: Error) -> String {
        if let e = error as? ESCLError { return e.errorDescription ?? "Error" }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorTimedOut: return "Timed out. Is the scanner on and on the same Wi-Fi?"
            case NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost: return "Cannot reach the scanner."
            case NSURLErrorNotConnectedToInternet: return "No network. Check Wi-Fi and Local Network permission."
            case NSURLErrorCancelled: return "Cancelled."
            default: break
            }
        }
        return error.localizedDescription
    }
}
