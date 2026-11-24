//
//  ScannerTestView.swift
//  QagazKit
//
//  Test screen: find scanner, connect, scan, see the received document.
//

import SwiftUI

struct ScannerTestView: View {
    @StateObject private var vm = ScannerTestViewModel()
    @State private var showLog = false

    private let accent = Color(red: 0.0, green: 0.48, blue: 1.0)
    private let bg = Color(red: 0.95, green: 0.95, blue: 0.97)

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    header
                    stepper
                    findCard
                    if vm.selected != nil { connectCard }
                    if vm.connection == .connected { scanCard }
                    if !vm.pages.isEmpty { resultCard }
                    logCard
                }
                .padding(16)
            }
        }
        .colorScheme(.light)
        .preferredColorScheme(.light)
        .onAppear { vm.startSearch() }
        .onDisappear { vm.stopSearch() }
    }

    // MARK: - Header and stepper

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Scanner Test")
                .font(.system(size: 30, weight: .bold))
            Text("Scan on your printer's glass or feeder and get the document here.")
                .font(.system(size: 15))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    private var stepper: some View {
        HStack(spacing: 0) {
            ForEach(ScannerTestViewModel.Step.allCases, id: \.rawValue) { step in
                let isDone = step.rawValue < vm.currentStep.rawValue
                let isCurrent = step == vm.currentStep
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(isDone ? Color.green : (isCurrent ? accent : Color.gray.opacity(0.25)))
                            .frame(width: 30, height: 30)
                        if isDone {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                        } else {
                            Text("\(step.rawValue + 1)")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(isCurrent ? .white : .gray)
                        }
                    }
                    Text(step.title)
                        .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                        .foregroundColor(isCurrent ? .primary : .secondary)
                }
                .frame(maxWidth: .infinity)
                if step != ScannerTestViewModel.Step.allCases.last {
                    Rectangle()
                        .fill(isDone ? Color.green : Color.gray.opacity(0.25))
                        .frame(height: 2)
                        .frame(maxWidth: 24)
                        .padding(.bottom, 20)
                }
            }
        }
        .padding(14)
        .background(card)
    }

    // MARK: - Card 1: Find

    private var findCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardTitle("1", "Find scanner", subtitle: "Phone and scanner must be on the same Wi-Fi.")

            if vm.scanners.isEmpty {
                HStack(spacing: 10) {
                    if vm.isSearching {
                        ProgressView()
                        Text("Searching...")
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                        Text("No scanners found. Check Wi-Fi and Local Network permission, or add by IP below.")
                    }
                }
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .padding(.vertical, 4)
            } else {
                ForEach(vm.scanners) { scanner in
                    scannerRow(scanner)
                }
                if vm.isSearching {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.8)
                        Text("Still searching...").font(.system(size: 13)).foregroundColor(.secondary)
                    }
                }
            }

            Button {
                vm.startSearch()
            } label: {
                Label("Search again", systemImage: "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(accent.opacity(0.12))
                    .foregroundColor(accent)
                    .cornerRadius(10)
            }

            Divider()

            Text("Or add by IP (example: 192.168.1.50 or 192.168.1.50:8080)")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            HStack {
                TextField("Scanner IP", text: $vm.manualIP)
                    .keyboardType(.numbersAndPunctuation)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .padding(10)
                    .background(Color.gray.opacity(0.12))
                    .cornerRadius(10)
                Button("Add") { vm.addManualScanner() }
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(accent)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .padding(16)
        .background(card)
    }

    private func scannerRow(_ scanner: ESCLScanner) -> some View {
        let isSelected = vm.selected?.id == scanner.id
        return Button {
            vm.connect(to: scanner)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "scanner")
                    .font(.system(size: 22))
                    .foregroundColor(accent)
                    .frame(width: 40, height: 40)
                    .background(accent.opacity(0.12))
                    .cornerRadius(10)
                VStack(alignment: .leading, spacing: 3) {
                    Text(scanner.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text("\(scanner.host):\(scanner.port)  \(scanner.isSecure ? "HTTPS" : "HTTP")")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "chevron.right")
                    .foregroundColor(isSelected ? .green : .gray)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).stroke(isSelected ? accent : Color.gray.opacity(0.25), lineWidth: isSelected ? 2 : 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Card 2: Connect

    private var connectCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardTitle("2", "Connection", subtitle: vm.selected?.name)

            switch vm.connection {
            case .idle:
                EmptyView()
            case .connecting:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Asking the scanner what it can do...").font(.system(size: 14)).foregroundColor(.secondary)
                }
            case .failed(let message):
                statusBanner(icon: "xmark.octagon.fill", color: .red, title: "Could not connect", text: message)
                Button {
                    if let s = vm.selected { vm.connect(to: s) }
                } label: {
                    primaryLabel("Try again", icon: "arrow.clockwise")
                }
            case .connected:
                statusBanner(icon: "checkmark.seal.fill", color: .green, title: "Connected", text: vm.capabilities?.makeAndModel ?? "")
                if let caps = vm.capabilities { capabilitiesGrid(caps) }
                Button("Disconnect") { vm.disconnect() }
                    .font(.system(size: 14))
                    .foregroundColor(.red)
            }
        }
        .padding(16)
        .background(card)
    }

    private func capabilitiesGrid(_ caps: ESCLCapabilities) -> some View {
        VStack(spacing: 0) {
            infoRow("eSCL version", caps.version)
            infoRow("Glass", caps.hasPlaten ? "Yes" : "No")
            infoRow("Feeder (ADF)", caps.hasFeeder ? "Yes" : "No")
            infoRow("Two-sided", caps.hasDuplex ? "Yes" : "No")
            infoRow("Formats", caps.formats.isEmpty ? "-" : caps.formats.map { $0.replacingOccurrences(of: "application/", with: "").replacingOccurrences(of: "image/", with: "") }.joined(separator: ", "))
            infoRow("Resolution", caps.resolutions.isEmpty ? "-" : caps.resolutions.map { "\($0)" }.joined(separator: ", ") + " dpi")
            infoRow("Max area", String(format: "%.1f x %.1f in", Double(caps.maxWidth) / 300, Double(caps.maxHeight) / 300), last: true)
        }
        .background(Color.gray.opacity(0.08))
        .cornerRadius(10)
    }

    // MARK: - Card 3: Scan

    private var scanCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            cardTitle("3", "Scan", subtitle: "Put a page on the glass, then press Start.")

            if let caps = vm.capabilities {
                settingRow("Source") {
                    Picker("Source", selection: $vm.settings.source) {
                        ForEach(ESCLInputSource.allCases.filter { $0 == .platen ? caps.hasPlaten : caps.hasFeeder }) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented)
                }
                settingRow("Color") {
                    Picker("Color", selection: $vm.settings.color) {
                        ForEach(ESCLColorMode.allCases.filter { caps.colorModes.isEmpty || caps.colorModes.contains($0.rawValue) }) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented)
                }
                if !caps.resolutions.isEmpty {
                    settingRow("Quality") {
                        Picker("Quality", selection: $vm.settings.dpi) {
                            ForEach(caps.resolutions.filter { $0 <= 1200 }, id: \.self) { Text("\($0) dpi").tag($0) }
                        }.pickerStyle(.segmented)
                    }
                }
                if caps.formats.count > 1 {
                    settingRow("Format") {
                        Picker("Format", selection: $vm.settings.format) {
                            ForEach(caps.formats, id: \.self) { Text($0.replacingOccurrences(of: "application/", with: "").replacingOccurrences(of: "image/", with: "").uppercased()).tag($0) }
                        }.pickerStyle(.segmented)
                    }
                }
            }

            switch vm.scanState {
            case .scanning:
                HStack(spacing: 10) {
                    ProgressView()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Scanning...").font(.system(size: 15, weight: .semibold))
                        Text(vm.pagesReceived == 0 ? "Wait for the scanner to finish." : "Pages received: \(vm.pagesReceived)")
                            .font(.system(size: 13)).foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Cancel") { vm.cancelScan() }
                        .foregroundColor(.red)
                }
                .padding(12)
                .background(accent.opacity(0.08))
                .cornerRadius(10)
            case .failed(let message):
                statusBanner(icon: "xmark.octagon.fill", color: .red, title: "Scan failed", text: message)
                startButton
            case .idle, .done:
                startButton
            }
        }
        .padding(16)
        .background(card)
    }

    private var startButton: some View {
        Button { vm.startScan() } label: {
            primaryLabel(vm.scanState == .done ? "Scan again" : "Start scan", icon: "play.fill")
        }
    }

    // MARK: - Card 4: Result

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            cardTitle("4", "Result", subtitle: "The document arrived on your phone.")

            statusBanner(icon: "checkmark.circle.fill", color: .green, title: "Scan received",
                         text: "\(vm.pages.count) page(s), \(vm.totalSizeText), \(String(format: "%.1f", vm.scanDuration)) s")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(vm.pages.enumerated()), id: \.element.id) { index, page in
                        VStack(spacing: 6) {
                            if let image = vm.image(for: page) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: 280)
                                    .background(Color.white)
                                    .cornerRadius(6)
                                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                            } else {
                                Text("Cannot show this page")
                                    .frame(width: 200, height: 280)
                                    .background(Color.gray.opacity(0.15))
                            }
                            Text("Page \(index + 1)").font(.system(size: 12)).foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical, 6)
            }

            VStack(spacing: 0) {
                infoRow("Pages", "\(vm.pages.count)")
                infoRow("Page size", vm.firstPageSizeText)
                infoRow("Total size", vm.totalSizeText)
                infoRow("Type", vm.pages.first?.mime ?? "-", last: true)
            }
            .background(Color.gray.opacity(0.08))
            .cornerRadius(10)

            if let url = vm.pdfURL {
                Button { vm.printScan() } label: {
                    primaryLabel("Print", icon: "printer.fill")
                }
                ShareLink(item: url) {
                    primaryLabel("Share / save PDF", icon: "square.and.arrow.up")
                }
            }
            Button("Clear result") { vm.scanAgain() }
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
        }
        .padding(16)
        .background(card)
    }

    // MARK: - Log

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation { showLog.toggle() }
            } label: {
                HStack {
                    Image(systemName: "terminal")
                    Text("Log (\(vm.log.count))").font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Image(systemName: showLog ? "chevron.up" : "chevron.down")
                }
                .foregroundColor(.primary)
            }
            if showLog {
                ForEach(vm.log) { line in
                    Text("\(line.time)  \(line.text)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(line.isError ? .red : .secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(16)
        .background(card)
    }

    // MARK: - Small pieces

    private var card: some View {
        RoundedRectangle(cornerRadius: 16).fill(Color.white)
    }

    private func cardTitle(_ number: String, _ title: String, subtitle: String?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(accent))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 18, weight: .bold))
                if let subtitle {
                    Text(subtitle).font(.system(size: 13)).foregroundColor(.secondary)
                }
            }
        }
    }

    private func statusBanner(icon: String, color: Color, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundColor(color).font(.system(size: 20))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(text).font(.system(size: 13)).foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(color.opacity(0.1))
        .cornerRadius(10)
    }

    private func infoRow(_ title: String, _ value: String, last: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.system(size: 14)).foregroundColor(.secondary)
                Spacer()
                Text(value).font(.system(size: 14, weight: .medium)).multilineTextAlignment(.trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            if !last { Divider().padding(.leading, 12) }
        }
    }

    private func settingRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundColor(.secondary)
            content()
        }
    }

    private func primaryLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 17, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(accent)
            .foregroundColor(.white)
            .cornerRadius(12)
    }
}
