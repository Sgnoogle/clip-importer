// Renders the README screenshot and the social preview image offscreen, from a real card or folder,
// at 2x (Retina), with a fake window frame on a gradient. No screen-recording permission needed.
//
// Build & run (from the repo root):
//   cd Sources && xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macos13.0" \
//     -sdk "$(xcrun --show-sdk-path --sdk macosx)" $(ls *.swift | grep -v AppDelegate) \
//     ../tools/screenshots/main.swift -o /tmp/render && cd ..
//   EXCLUDE="C0002.MP4" /tmp/render "/Volumes/<card>" docs/screenshot.png docs/icon.png \
//     docs/social-preview.png en Resources/strings.json "SD Card"
//
// Arguments: card/folder, screenshot out, icon png, social preview out, language code,
//            strings.json, name shown for the card.
// EXCLUDE: comma-separated file names to leave out (privacy: e.g. clips showing shipping labels).
// Flags shown in the picture are set in memory only and never saved.
// ALWAYS look at every thumbnail before publishing: they are real footage.

import AppKit
import SwiftUI

/// Finestra "da vetrina": barra del titolo con i semafori, angoli arrotondati, ombra, su sfondo sfumato.
struct Showcase: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.98, green: 0.55, blue: 0.20), Color(red: 0.55, green: 0.25, blue: 0.75)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 0) {
                ZStack {
                    Color(nsColor: .windowBackgroundColor)
                    HStack(spacing: 8) {
                        Circle().fill(Color(red: 1, green: 0.37, blue: 0.34)).frame(width: 12, height: 12)
                        Circle().fill(Color(red: 1, green: 0.74, blue: 0.18)).frame(width: 12, height: 12)
                        Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.25)).frame(width: 12, height: 12)
                        Spacer()
                    }.padding(.leading, 14)
                    Text("Clip Importer").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                }
                .frame(height: 28)
                ContentView().background(Color(nsColor: .windowBackgroundColor))
                    .environment(\.controlActiveState, .key)
            }
            .frame(width: 1240, height: 760)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.black.opacity(0.15), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.35), radius: 30, y: 16)
        }
        .frame(width: 1400, height: 900)
    }
}

struct SocialCard: View {
    let hero: NSImage
    let icon: NSImage
    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(red: 0.98, green: 0.55, blue: 0.20), Color(red: 0.55, green: 0.25, blue: 0.75)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(nsImage: hero).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                .frame(width: 900, height: 579).offset(x: 610, y: 215)
            VStack(alignment: .leading, spacing: 14) {
                Image(nsImage: icon).resizable().frame(width: 120, height: 120)
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 5)
                Text("Clip Importer").font(.system(size: 64, weight: .bold, design: .rounded)).foregroundColor(.white)
                Text("Import videos & photos\nfrom Sony cameras on Mac").font(.system(size: 30, weight: .semibold))
                    .foregroundColor(.white.opacity(0.95)).fixedSize()
                Text("Free & open source\nA PlayMemories Home alternative").font(.system(size: 22, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
            }
            .padding(.leading, 64).padding(.top, 70)
        }
        .frame(width: 1280, height: 640)
        .clipped()
    }
}
final class KeyWindow: NSWindow { override var canBecomeKey: Bool { true }; override var canBecomeMain: Bool { true } }

MainActor.assumeIsolated {
    Lang.use(CommandLine.arguments.count > 5 ? CommandLine.arguments[5] : "en",
             stringsFile: URL(fileURLWithPath: CommandLine.arguments[6 < CommandLine.arguments.count ? 6 : 0]))
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.appearance = NSAppearance(named: .aqua)
    let state = AppState.shared
    let card = URL(fileURLWithPath: CommandLine.arguments[1])
    let savedFlags = state.flags
    state.mediaFilter = .all
    state.hideImported = false
    state.sortKey = .name
    state.ascending = true
    state.thumbSize = 210
    state.open(Source(id: card, name: CommandLine.arguments.count > 7 ? CommandLine.arguments[7] : "SD Card", isVolume: true))
    RunLoop.main.run(until: Date().addingTimeInterval(4))
    let excluded = Set((ProcessInfo.processInfo.environment["EXCLUDE"] ?? "").split(separator: ",").map(String.init))
    state.clips.removeAll { excluded.contains($0.name) }
    let all = state.visibleClips
    print("elementi:", all.count, all.map(\.name).joined(separator: " "))
    // Qualche etichetta e una selezione per mostrare le funzioni (in memoria, non salvate)
    if all.count > 8 {
        state.flags[ImportedStore.key(all[1])] = .pick
        state.flags[ImportedStore.key(all[2])] = .reject
        state.flags[ImportedStore.key(all[5])] = .pick
        state.flags[ImportedStore.key(all[8])] = .pick
    }
    let host = NSHostingView(rootView: Showcase().environmentObject(state))
    host.frame = NSRect(x: 0, y: 0, width: 1400, height: 900)
    let win = KeyWindow(contentRect: NSRect(x: 0, y: 0, width: 1400, height: 900), styleMask: [.borderless], backing: .buffered, defer: false)
    win.appearance = NSAppearance(named: .aqua)
    win.contentView = host
    win.alphaValue = 0          // invisibile, ma sullo schermo Retina: render a 2x
    win.ignoresMouseEvents = true
    win.orderFrontRegardless()
    win.makeKeyAndOrderFront(nil)
    win.makeMain()
    app.activate(ignoringOtherApps: true)
    RunLoop.main.run(until: Date().addingTimeInterval(5))
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2800, pixelsHigh: 1800, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = host.bounds.size
    host.cacheDisplay(in: host.bounds, to: rep)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
    // Anteprima social 1280×640
    let heroImage = NSImage(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))!
    let icon = NSImage(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3]))!
    let social = SocialCard(hero: heroImage, icon: icon)
    let host2 = NSHostingView(rootView: social)
    host2.frame = NSRect(x: 0, y: 0, width: 1280, height: 640)
    let win2 = KeyWindow(contentRect: host2.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    win2.contentView = host2; win2.alphaValue = 0; win2.orderFrontRegardless()
    RunLoop.main.run(until: Date().addingTimeInterval(1.5))
    let rep2 = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1280, pixelsHigh: 640, bitsPerSample: 8,
                                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                bytesPerRow: 0, bitsPerPixel: 0)!
    rep2.size = host2.bounds.size
    host2.cacheDisplay(in: host2.bounds, to: rep2)
    try! rep2.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[4]))
    state.flags = savedFlags
    print("ok")
}
