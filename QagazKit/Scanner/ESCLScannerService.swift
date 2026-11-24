//
//  ESCLScannerService.swift
//  QagazKit
//
//  Test code: find scanners (Bonjour _uscan) and scan with eSCL / AirScan.
//

import Foundation

// MARK: - Models

nonisolated struct ESCLScanner: Identifiable, Equatable {
    let id: String          // Bonjour service name
    let name: String
    let host: String
    let port: Int
    let isSecure: Bool
    let rootPath: String    // usually "eSCL"
    let formats: [String]   // from TXT "pdl"
    let sources: [String]   // from TXT "is"

    var baseURL: URL? {
        let scheme = isSecure ? "https" : "http"
        let hostPart = host.contains(":") ? "[\(host)]" : host
        let path = rootPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: "\(scheme)://\(hostPart):\(port)/\(path)")
    }
}

nonisolated struct ESCLCapabilities {
    var makeAndModel: String = "Unknown"
    var version: String = "-"
    var hasPlaten = false
    var hasFeeder = false
    var hasDuplex = false
    var colorModes: [String] = []
    var formats: [String] = []
    var resolutions: [Int] = []
    var maxWidth: Int = 2550    // in 1/300 inch (Letter by default)
    var maxHeight: Int = 3300
}

nonisolated enum ESCLColorMode: String, CaseIterable, Identifiable {
    case color = "RGB24"
    case gray = "Grayscale8"
    case blackWhite = "BlackAndWhite1"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .color: return "Color"
        case .gray: return "Gray"
        case .blackWhite: return "B&W"
        }
    }
}

nonisolated enum ESCLInputSource: String, CaseIterable, Identifiable {
    case platen = "Platen"
    case feeder = "Feeder"
    var id: String { rawValue }
    var title: String { self == .platen ? "Glass" : "Feeder (ADF)" }
}

nonisolated struct ESCLScanSettings {
    var source: ESCLInputSource = .platen
    var color: ESCLColorMode = .color
    var dpi: Int = 300
    var format: String = "image/jpeg"
}

nonisolated struct ESCLPage: Identifiable {
    let id = UUID()
    let data: Data
    let mime: String
}

nonisolated enum ESCLError: LocalizedError {
    case badURL
    case http(Int, String)
    case noLocation
    case noPages
    case cancelled
    case parse

    var errorDescription: String? {
        switch self {
        case .badURL: return "Wrong scanner address."
        case .http(let code, let step): return "Scanner answered \(code) at step: \(step)."
        case .noLocation: return "Scanner did not return a job address."
        case .noPages: return "Scanner returned no pages. Put a page on the glass and try again."
        case .cancelled: return "Scan was cancelled."
        case .parse: return "Could not read the scanner answer."
        }
    }
}

// MARK: - Tiny XML tree

nonisolated final class XMLNode {
    let name: String        // without namespace prefix
    var text = ""
    var children: [XMLNode] = []
    init(name: String) { self.name = name }

    func first(_ name: String) -> XMLNode? {
        if self.name == name { return self }
        for child in children {
            if let found = child.first(name) { return found }
        }
        return nil
    }

    func all(_ name: String) -> [XMLNode] {
        var result: [XMLNode] = []
        if self.name == name { result.append(self) }
        for child in children { result += child.all(name) }
        return result
    }
}

nonisolated private final class XMLTreeParser: NSObject, XMLParserDelegate {
    private var stack: [XMLNode] = []
    private(set) var root: XMLNode?

    static func parse(_ data: Data) -> XMLNode? {
        let delegate = XMLTreeParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.root
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let short = elementName.split(separator: ":").last.map(String.init) ?? elementName
        let node = XMLNode(name: short)
        if let parent = stack.last { parent.children.append(node) } else { root = node }
        stack.append(node)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        stack.last?.text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        stack.last?.text = stack.last?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        _ = stack.popLast()
    }
}

// MARK: - Discovery (Bonjour)

nonisolated final class ESCLDiscovery: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    var onUpdate: (([ESCLScanner]) -> Void)?

    private let browsers: [NetServiceBrowser] = [NetServiceBrowser(), NetServiceBrowser()]
    private var services: [NetService] = []
    private var found: [String: ESCLScanner] = [:]

    func start() {
        stop()
        found.removeAll()
        services.removeAll()
        onUpdate?([])
        for browser in browsers { browser.delegate = self }
        browsers[0].searchForServices(ofType: "_uscan._tcp.", inDomain: "local.")
        browsers[1].searchForServices(ofType: "_uscans._tcp.", inDomain: "local.")
    }

    func stop() {
        browsers.forEach { $0.stop() }
        services.forEach { $0.stop() }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        services.append(service)
        service.delegate = self
        service.resolve(withTimeout: 8)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        var txt: [String: String] = [:]
        if let data = sender.txtRecordData() {
            for (key, value) in NetService.dictionary(fromTXTRecord: data) {
                txt[key] = String(data: value, encoding: .utf8) ?? ""
            }
        }
        guard let host = Self.pickAddress(from: sender) ?? sender.hostName else { return }
        let secure = sender.type.contains("_uscans")
        let port = sender.port > 0 ? sender.port : (secure ? 443 : 80)
        let rs = txt["rs"].flatMap { $0.isEmpty ? nil : $0 } ?? "eSCL"
        let name = txt["ty"].flatMap { $0.isEmpty ? nil : $0 } ?? sender.name
        let scanner = ESCLScanner(
            id: sender.name + (secure ? "#s" : ""),
            name: name,
            host: host,
            port: port,
            isSecure: secure,
            rootPath: rs,
            formats: (txt["pdl"] ?? "").split(separator: ",").map(String.init),
            sources: (txt["is"] ?? "").split(separator: ",").map(String.init)
        )
        DispatchQueue.main.async {
            // Keep the HTTPS entry only if HTTP one with the same name is missing.
            if scanner.isSecure, self.found[sender.name] != nil { return }
            if !scanner.isSecure { self.found[sender.name + "#s"] = nil }
            self.found[scanner.id] = scanner
            self.onUpdate?(self.found.values.sorted { $0.name < $1.name })
        }
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {}

    /// Prefer IPv4. Skip link-local IPv6.
    private static func pickAddress(from service: NetService) -> String? {
        var ipv4: String?
        var ipv6: String?
        for data in service.addresses ?? [] {
            let ip: String? = data.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return nil }
                let sa = base.assumingMemoryBound(to: sockaddr.self)
                var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                guard getnameinfo(sa, socklen_t(data.count), &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0
                else { return nil }
                return String(cString: buffer)
            }
            guard let ip else { continue }
            if ip.contains(":") {
                if !ip.lowercased().hasPrefix("fe80") { ipv6 = ipv6 ?? ip }
            } else {
                ipv4 = ipv4 ?? ip
            }
        }
        return ipv4 ?? ipv6
    }
}

// MARK: - Client (eSCL over HTTP)

final class ESCLClient: NSObject, URLSessionDelegate {
    private let scanner: ESCLScanner
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 600
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    private var jobURL: URL?
    private var cancelled = false

    init(scanner: ESCLScanner) {
        self.scanner = scanner
    }

    // Scanners use self-signed certificates. We trust them only for the scanner host.
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           challenge.protectionSpace.host == scanner.host,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    func fetchCapabilities() async throws -> ESCLCapabilities {
        guard let base = scanner.baseURL else { throw ESCLError.badURL }
        let (data, response) = try await session.data(from: base.appendingPathComponent("ScannerCapabilities"))
        try Self.check(response, step: "ScannerCapabilities")
        guard let root = XMLTreeParser.parse(data) else { throw ESCLError.parse }

        var caps = ESCLCapabilities()
        caps.makeAndModel = root.first("MakeAndModel")?.text ?? scanner.name
        caps.version = root.first("Version")?.text ?? "-"
        caps.hasPlaten = root.first("PlatenInputCaps") != nil
        caps.hasFeeder = root.first("AdfSimplexInputCaps") != nil || root.first("Adf") != nil
        caps.hasDuplex = root.first("AdfDuplexInputCaps") != nil

        let source = root.first("PlatenInputCaps") ?? root.first("AdfSimplexInputCaps") ?? root
        if let width = Int(source.first("MaxWidth")?.text ?? "") { caps.maxWidth = width }
        if let height = Int(source.first("MaxHeight")?.text ?? "") { caps.maxHeight = height }

        caps.colorModes = Array(Set(root.all("ColorMode").map(\.text))).sorted()
        caps.formats = Array(Set(root.all("DocumentFormat").map(\.text).filter { !$0.isEmpty })).sorted()
        let dpis = root.all("DiscreteResolution").compactMap { Int($0.first("XResolution")?.text ?? "") }
        caps.resolutions = Array(Set(dpis)).sorted()
        return caps
    }

    /// Runs a scan and returns all pages. `progress` is called after each page.
    func scan(settings: ESCLScanSettings, capabilities: ESCLCapabilities,
              progress: @escaping (Int) -> Void) async throws -> [ESCLPage] {
        guard let base = scanner.baseURL else { throw ESCLError.badURL }
        cancelled = false

        // 1. Create the job
        var request = URLRequest(url: base.appendingPathComponent("ScanJobs"))
        request.httpMethod = "POST"
        request.setValue("text/xml", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.scanSettingsXML(settings, caps: capabilities).data(using: .utf8)
        let (_, response) = try await session.data(for: request)
        try Self.check(response, step: "Create job", ok: [200, 201])

        guard let http = response as? HTTPURLResponse,
              let location = http.value(forHTTPHeaderField: "Location"),
              let job = URL(string: location, relativeTo: base)?.absoluteURL else { throw ESCLError.noLocation }
        jobURL = job

        // 2. Get pages
        var pages: [ESCLPage] = []
        var busyRetries = 0
        while !cancelled {
            var pageRequest = URLRequest(url: job.appendingPathComponent("NextDocument"))
            pageRequest.timeoutInterval = 180
            let (data, pageResponse) = try await session.data(for: pageRequest)
            let code = (pageResponse as? HTTPURLResponse)?.statusCode ?? 0
            if code == 200 {
                let mime = (pageResponse as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? settings.format
                pages.append(ESCLPage(data: data, mime: mime))
                progress(pages.count)
                busyRetries = 0
                // Glass gives one page per job.
                if settings.source == .platen { break }
            } else if code == 404 || code == 410 {
                break   // no more pages
            } else if code == 503, busyRetries < 20 {
                busyRetries += 1
                try await Task.sleep(nanoseconds: 1_000_000_000)
            } else {
                await finishJob()
                throw ESCLError.http(code, "Get page")
            }
        }
        await finishJob()
        if cancelled { throw ESCLError.cancelled }
        if pages.isEmpty { throw ESCLError.noPages }
        return pages
    }

    func cancel() {
        cancelled = true
        session.invalidateAndCancel()
    }

    private func finishJob() async {
        guard let job = jobURL else { return }
        var request = URLRequest(url: job)
        request.httpMethod = "DELETE"
        request.timeoutInterval = 10
        _ = try? await URLSession.shared.data(for: request)
        jobURL = nil
    }

    private static func check(_ response: URLResponse, step: String, ok: [Int] = [200]) throws {
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if !ok.contains(code) { throw ESCLError.http(code, step) }
    }

    private static func scanSettingsXML(_ s: ESCLScanSettings, caps: ESCLCapabilities) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <scan:ScanSettings xmlns:pwg="http://www.pwg.org/schemas/2010/12/sm" xmlns:scan="http://schemas.hp.com/imaging/escl/2011/05/03">
          <pwg:Version>2.0</pwg:Version>
          <pwg:ScanRegions>
            <pwg:ScanRegion>
              <pwg:ContentRegionUnits>escl:ThreeHundredthsOfInches</pwg:ContentRegionUnits>
              <pwg:Height>\(caps.maxHeight)</pwg:Height>
              <pwg:Width>\(caps.maxWidth)</pwg:Width>
              <pwg:XOffset>0</pwg:XOffset>
              <pwg:YOffset>0</pwg:YOffset>
            </pwg:ScanRegion>
          </pwg:ScanRegions>
          <scan:InputSource>\(s.source.rawValue)</scan:InputSource>
          <scan:ColorMode>\(s.color.rawValue)</scan:ColorMode>
          <scan:XResolution>\(s.dpi)</scan:XResolution>
          <scan:YResolution>\(s.dpi)</scan:YResolution>
          <pwg:DocumentFormat>\(s.format)</pwg:DocumentFormat>
        </scan:ScanSettings>
        """
    }
}
