//
//  PrinterDiscovery.swift
//  QagazKit
//
//  Finds AirPrint printers on Wi-Fi (Bonjour _ipp / _ipps) and checks they are reachable.
//

import SwiftUI
import UIKit
import Combine

struct DiscoveredPrinter: Identifiable {
    let id = UUID()
    let name: String
    let printer: UIPrinter
}

final class PrinterDiscovery: NSObject, ObservableObject, NetServiceBrowserDelegate, NetServiceDelegate {

    enum State { case searching, found, none }

    @Published private(set) var state: State = .searching
    @Published private(set) var printers: [DiscoveredPrinter] = []
    @Published var connectingID: UUID?
    @Published var connectedID: UUID?
    @Published var errorText: String?

    var connected: DiscoveredPrinter? { printers.first { $0.id == connectedID } }

    private let ippBrowser = NetServiceBrowser()
    private let ippsBrowser = NetServiceBrowser()
    private var services: [NetService] = []

    override init() {
        super.init()
        ippBrowser.delegate = self
        ippsBrowser.delegate = self
    }

    func start() {
        stop()
        state = .searching
        errorText = nil
        services.removeAll()
        printers.removeAll()
        connectedID = nil
        ippBrowser.searchForServices(ofType: "_ipp._tcp.", inDomain: "local.")
        ippsBrowser.searchForServices(ofType: "_ipps._tcp.", inDomain: "local.")
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self, self.printers.isEmpty else { return }
            self.state = .none
        }
    }

    func stop() {
        ippBrowser.stop()
        ippsBrowser.stop()
    }

    func connect(_ item: DiscoveredPrinter) {
        connectingID = item.id
        errorText = nil
        item.printer.contactPrinter { [weak self] reachable in
            DispatchQueue.main.async {
                guard let self else { return }
                self.connectingID = nil
                self.connectedID = reachable ? item.id : nil
                if !reachable { self.errorText = "Cannot reach \(item.name). Is it on and on the same Wi-Fi?" }
            }
        }
    }

    // MARK: - Bonjour

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        services.append(service)
        service.delegate = self
        service.resolve(withTimeout: 8)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        let secure = sender.type.contains("ipps")
        let scheme = secure ? "ipps" : "ipp"
        let port = sender.port > 0 ? sender.port : (secure ? 443 : 631)
        let host = Self.ipv4(from: sender) ?? sender.hostName ?? "local."
        let txt = sender.txtRecordData().map { NetService.dictionary(fromTXTRecord: $0) } ?? [:]
        func text(_ key: String) -> String? {
            txt[key].flatMap { String(data: $0, encoding: .utf8) }.flatMap { $0.isEmpty ? nil : $0 }
        }
        var path = text("rp") ?? "ipp/print"
        if path.hasPrefix("/") { path.removeFirst() }
        guard let url = URL(string: "\(scheme)://\(host):\(port)/\(path)") else { return }
        let name = text("ty") ?? text("note") ?? sender.name

        DispatchQueue.main.async {
            guard !self.printers.contains(where: { $0.printer.url == url || $0.name == name }) else { return }
            self.printers.append(DiscoveredPrinter(name: name, printer: UIPrinter(url: url)))
            self.state = .found
        }
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {}

    private static func ipv4(from service: NetService) -> String? {
        for data in service.addresses ?? [] {
            var storage = sockaddr_storage()
            (data as NSData).getBytes(&storage, length: MemoryLayout<sockaddr_storage>.size)
            guard storage.ss_family == UInt8(AF_INET) else { continue }
            var addr = withUnsafePointer(to: &storage) {
                $0.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
            }
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            if inet_ntop(AF_INET, &addr.sin_addr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil {
                return String(cString: buffer)
            }
        }
        return nil
    }
}
