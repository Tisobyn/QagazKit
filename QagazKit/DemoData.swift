//
//  DemoData.swift
//  QagazKit
//
//  Demo mode: run the app with the launch argument "-demo" to use a fake
//  printer and a fake scanner. Good for screenshots and trying the UI
//  without real devices.
//

import UIKit

enum Demo {
    static let isOn = ProcessInfo.processInfo.arguments.contains("-demo")

    // MARK: Printers

    static var printers: [DiscoveredPrinter] {
        [
            DiscoveredPrinter(name: "Brother HL-L2350DW", printer: UIPrinter(url: URL(string: "ipp://192.168.1.50:631/ipp/print")!)),
            DiscoveredPrinter(name: "HP LaserJet Pro M404", printer: UIPrinter(url: URL(string: "ipp://192.168.1.61:631/ipp/print")!)),
            DiscoveredPrinter(name: "Canon PIXMA TR8650", printer: UIPrinter(url: URL(string: "ipp://192.168.1.72:631/ipp/print")!)),
        ]
    }

    // MARK: Scanner

    static let scanners = [
        ESCLScanner(id: "demo-brother", name: "Brother DCP-L2550DW", host: "192.168.1.42", port: 80,
                    isSecure: false, rootPath: "eSCL", formats: ["image/jpeg", "application/pdf"], sources: ["platen", "adf"]),
        ESCLScanner(id: "demo-epson", name: "Epson ET-2850 Series", host: "192.168.1.43", port: 443,
                    isSecure: true, rootPath: "eSCL", formats: ["image/jpeg"], sources: ["platen"]),
    ]

    static var capabilities: ESCLCapabilities {
        var caps = ESCLCapabilities()
        caps.makeAndModel = "Brother DCP-L2550DW"
        caps.version = "2.63"
        caps.hasPlaten = true
        caps.hasFeeder = true
        caps.hasDuplex = false
        caps.colorModes = ["BlackAndWhite1", "Grayscale8", "RGB24"]
        caps.formats = ["application/pdf", "image/jpeg"]
        caps.resolutions = [100, 200, 300, 600]
        caps.maxWidth = 2550
        caps.maxHeight = 3507
        return caps
    }

    // MARK: Pictures

    /// A fake photo: sky, sun and hills.
    static func photo() -> UIImage {
        let size = CGSize(width: 1200, height: 800)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let c = ctx.cgContext
            let colors = [UIColor(red: 0.99, green: 0.62, blue: 0.35, alpha: 1).cgColor,
                          UIColor(red: 0.35, green: 0.55, blue: 0.9, alpha: 1).cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
            c.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size.height), end: .zero, options: [])
            UIColor(white: 1, alpha: 0.9).setFill()
            c.fillEllipse(in: CGRect(x: 800, y: 150, width: 140, height: 140))
            UIColor(red: 0.2, green: 0.35, blue: 0.35, alpha: 1).setFill()
            c.fillEllipse(in: CGRect(x: -200, y: 520, width: 900, height: 600))
            UIColor(red: 0.13, green: 0.25, blue: 0.28, alpha: 1).setFill()
            c.fillEllipse(in: CGRect(x: 400, y: 600, width: 1100, height: 700))
        }
    }

    /// A fake scanned page (an invoice).
    static func scannedPage() -> UIImage {
        let size = CGSize(width: 1275, height: 1650)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIColor(white: 0.98, alpha: 1).setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            func text(_ s: String, _ x: CGFloat, _ y: CGFloat, _ font: UIFont, _ color: UIColor = .black) {
                (s as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [.font: font, .foregroundColor: color])
            }
            text("INVOICE", 100, 110, .systemFont(ofSize: 70, weight: .bold))
            text("No. 2041  ·  24 Nov 2026", 100, 200, .systemFont(ofSize: 32), .darkGray)
            text("Qagaz Studio\n12 Example Street\nAlmaty", 800, 120, .systemFont(ofSize: 30), .darkGray)
            UIColor.black.setFill()
            UIRectFill(CGRect(x: 100, y: 320, width: 1075, height: 4))
            let rows = [("Poster print A3", "4", "$ 48.00"), ("Business cards", "250", "$ 35.00"),
                        ("Photo paper A4", "20", "$ 22.50"), ("Binding", "1", "$ 6.00")]
            for (i, row) in rows.enumerated() {
                let y = 370 + CGFloat(i) * 90
                text(row.0, 100, y, .systemFont(ofSize: 34))
                text(row.1, 760, y, .systemFont(ofSize: 34))
                text(row.2, 960, y, .systemFont(ofSize: 34))
            }
            UIRectFill(CGRect(x: 100, y: 780, width: 1075, height: 2))
            text("Total", 760, 810, .systemFont(ofSize: 40, weight: .bold))
            text("$ 111.50", 930, 810, .systemFont(ofSize: 40, weight: .bold))
            text("Thank you!", 100, 1500, .italicSystemFont(ofSize: 36), .gray)
        }
    }
}
