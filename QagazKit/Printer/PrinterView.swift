//
//  PrinterView.swift
//  QagazKit
//
//  Find a printer, connect, pick a photo or PDF, print it.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import Combine

enum PrintContent {
    case image(UIImage)
    case pdf(Data)
}

@MainActor
final class PrinterViewModel: ObservableObject {
    @Published var content: PrintContent?
    @Published var fileName = ""
    @Published var message: String?
    @Published var isPrinting = false

    var preview: UIImage? {
        switch content {
        case .image(let image): return image
        case .pdf(let data):
            return PDFPreview.firstPage(of: data)
        case nil: return nil
        }
    }

    func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
            content = .image(image)
            fileName = "Photo"
            message = nil
        } else {
            message = "Could not open this photo."
        }
    }

    func loadFile(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { message = "Could not read this file."; return }
        if url.pathExtension.lowercased() == "pdf" {
            content = .pdf(data)
        } else if let image = UIImage(data: data) {
            content = .image(image)
        } else {
            message = "This file type is not supported."
            return
        }
        fileName = url.lastPathComponent
        message = nil
    }

    func print(to item: DiscoveredPrinter) {
        guard let content else { return }
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = fileName.isEmpty ? "QagazKit" : fileName
        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        switch content {
        case .image(let image): controller.printingItem = image
        case .pdf(let data): controller.printingItem = data
        }
        isPrinting = true
        message = nil
        controller.print(to: item.printer) { [weak self] _, completed, error in
            Task { @MainActor in
                guard let self else { return }
                self.isPrinting = false
                if let error {
                    self.message = "Print failed: \(error.localizedDescription)"
                } else if completed {
                    self.message = "Sent to \(item.name)."
                }
            }
        }
    }
}

import PDFKit
enum PDFPreview {
    static func firstPage(of data: Data) -> UIImage? {
        PDFDocument(data: data)?.page(at: 0)?.thumbnail(of: CGSize(width: 600, height: 800), for: .mediaBox)
    }
}

struct PrinterView: View {
    @StateObject private var discovery = PrinterDiscovery()
    @StateObject private var vm = PrinterViewModel()
    @State private var photo: PhotosPickerItem?
    @State private var showFiles = false

    var body: some View {
        NavigationStack {
            List {
                Section("Printers") { printerRows }
                Section("Document") { documentRows }
                if let message = vm.message ?? discovery.errorText {
                    Section { Text(message).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Printer")
            .toolbar {
                Button { discovery.start() } label: { Image(systemName: "arrow.clockwise") }
            }
            .safeAreaInset(edge: .bottom) { printBar }
        }
        .onAppear { discovery.start() }
        .onDisappear { discovery.stop() }
        .onChange(of: photo) { item in Task { await vm.loadPhoto(item) } }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.pdf, .image]) { vm.loadFile($0) }
    }

    @ViewBuilder private var printerRows: some View {
        if discovery.printers.isEmpty {
            if discovery.state == .searching {
                HStack(spacing: 10) { ProgressView(); Text("Searching...") }
            } else {
                Text("No printers found. Check Wi-Fi and Local Network permission.")
                    .foregroundStyle(.secondary)
            }
        }
        ForEach(discovery.printers) { item in
            Button { discovery.connect(item) } label: {
                HStack {
                    Image(systemName: "printer")
                    Text(item.name)
                    Spacer()
                    if discovery.connectingID == item.id {
                        ProgressView()
                    } else if discovery.connectedID == item.id {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                }
            }
            .tint(.primary)
        }
    }

    @ViewBuilder private var documentRows: some View {
        PhotosPicker(selection: $photo, matching: .images) {
            Label("Choose photo", systemImage: "photo")
        }
        Button { showFiles = true } label: { Label("Choose PDF or image file", systemImage: "doc") }
        if let image = vm.preview {
            VStack(spacing: 6) {
                Image(uiImage: image).resizable().scaledToFit().frame(height: 220)
                Text(vm.fileName).font(.footnote).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var printBar: some View {
        let printer = discovery.connected
        return Button {
            if let printer { vm.print(to: printer) }
        } label: {
            Group {
                if vm.isPrinting { ProgressView() } else { Label("Print", systemImage: "printer.fill") }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 14)
            .background(printer != nil && vm.content != nil ? Color.accentColor : Color.gray.opacity(0.4))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(printer == nil || vm.content == nil || vm.isPrinting)
        .padding()
        .background(.bar)
    }
}
