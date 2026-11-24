//
//  ContentView.swift
//  QagazKit
//
//  Created by Tiso on 24.11.2026.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            PrinterView()
                .tabItem { Label("Print", systemImage: "printer") }
            ScannerTestView()
                .tabItem { Label("Scan", systemImage: "scanner") }
        }
    }
}

#Preview {
    ContentView()
}
