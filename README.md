<div align="center">

# 📄 QagazKit

**Find your printer. Scan a page. Print it. All from your iPhone.**

![Platform](https://img.shields.io/badge/platform-iOS%2016%2B-blue?logo=apple)
![Swift](https://img.shields.io/badge/Swift-5-orange?logo=swift)
![UI](https://img.shields.io/badge/UI-SwiftUI-informational)
![Deps](https://img.shields.io/badge/dependencies-none-brightgreen)
![License](https://img.shields.io/badge/license-MIT-lightgrey)

</div>

---

## ✨ Features

| | Feature | What it does |
|---|---|---|
| 🖨️ | **Find printers** | Searches your Wi-Fi for AirPrint printers (Bonjour `_ipp` / `_ipps`). |
| 🔗 | **Connect** | Taps a printer and checks it is reachable. |
| 📤 | **Print** | Prints a photo, an image file or a PDF. |
| 📠 | **Find scanners** | Searches for eSCL / AirScan scanners (`_uscan` / `_uscans`). Can also add by IP. |
| 🖼️ | **Scan** | Scan from glass or feeder. Choose color, quality and format. |
| 📑 | **Multi-page PDF** | Pages are joined into one PDF. Share it or print it. |

No server. No account. No third-party libraries.

## 📱 How it looks

> Example data, for illustration.

```
┌─────────────────────────────┐
│  Printer                 ⟳  │
├─────────────────────────────┤
│  PRINTERS                   │
│  🖨  Brother HL-L2350DW   ✅ │
│  🖨  HP LaserJet Pro M404   │
│  DOCUMENT                   │
│  🖼  Choose photo           │
│  📄 Choose PDF or image     │
│       [ vacation.jpg ]      │
│                             │
│  [        🖨  Print       ] │
└─────────────────────────────┘
```

Example scan log:

```
10:42:01  Searching for scanners (_uscan._tcp, _uscans._tcp)...
10:42:03  Found: Brother DCP-L2550DW at 192.168.1.42:80
10:42:05  Connected: Brother DCP-L2550DW, eSCL 2.63
10:42:09  Scan started: Platen, RGB24, 300 dpi, image/jpeg
10:42:17  Page 1 received
10:42:17  Done: 1 page(s) in 8.1 s
```

## 🚀 Getting started

1. Open `QagazKit.xcodeproj` in Xcode.
2. Pick your iPhone (the simulator cannot see real printers).
3. Run. Allow **Local Network** access when iOS asks.
4. Make sure the phone and the printer are on the **same Wi-Fi**.

## 🧩 How it works

```
QagazKit/
├── Printer/
│   ├── PrinterDiscovery.swift   # Bonjour search + connect check
│   └── PrinterView.swift        # pick a file, print it
├── Scanner/
│   ├── ESCLScannerService.swift # discovery + eSCL client (HTTP/XML)
│   ├── ScannerTestViewModel.swift
│   └── ScannerTestView.swift    # find, connect, scan, result
├── ContentView.swift            # tabs: Print / Scan
└── Info.plist (project root)    # Bonjour + local network keys
```

- **Printing** uses Apple's `UIPrinter` and `UIPrintInteractionController`.
- **Scanning** speaks the eSCL protocol: `GET /ScannerCapabilities`, `POST /ScanJobs`, then `GET /NextDocument` for each page.
- Scanners often use self-signed HTTPS. The app trusts the certificate only for the scanner's own address.

## 🛠️ Troubleshooting

| Problem | Try this |
|---|---|
| No printers or scanners found | Check Wi-Fi, and that Local Network is allowed in Settings. |
| Cannot connect | Turn the device on, and use the same network. Guest Wi-Fi often blocks discovery. |
| Scanner not listed | Add it by IP in the Scan tab, for example `192.168.1.50`. |

## 📄 License

Open source under the [MIT License](LICENSE). Everyone can use it, change it and share it.
