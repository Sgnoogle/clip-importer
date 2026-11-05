import AppKit
import Quartz
import SwiftUI

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate, NSMenuItemValidation,
                         QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    private static var instance: AppDelegate?

    let state = AppState.shared
    private var window: NSWindow?
    private var statusItem: NSStatusItem?
    private let launchedInBackground = CommandLine.arguments.contains("--background")

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        instance = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    // MARK: - Ciclo di vita

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
        buildStatusItem()

        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "didConfigureLoginItem") {
            defaults.set(true, forKey: "didConfigureLoginItem")
            state.launchAtLogin = true          // al primo avvio si attiva da solo
        } else if LoginItem.isEnabled {
            LoginItem.setEnabled(true)          // aggiorna il percorso se l'app è stata spostata
        }

        state.onWantsWindow = { [weak self] in self?.showWindow() }

        // ⌥ trasforma "Importa" in "Sposta", come nel Finder
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            let held = event.modifierFlags.contains(.option)
            if AppState.shared.optionHeld != held { AppState.shared.optionHeld = held }
            return event
        }
        // Tasti senza ⌘ (spazio, ⌫) sulla griglia: come nel Finder. Nei campi di testo restano normali.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let w = self.window, event.window === w, w.attachedSheet == nil,
                  !(w.firstResponder is NSText) else { return event }
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
            // Frecce ← → (con ⇧ allargano la selezione)
            if mods.subtracting(.shift).isEmpty, event.keyCode == 123 || event.keyCode == 124 {
                self.state.moveSelection(by: event.keyCode == 124 ? 1 : -1, extend: mods.contains(.shift))
                return nil
            }
            guard mods.isEmpty else { return event }
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "p": self.state.flagSelection(.pick); return nil
            case "x": self.state.flagSelection(.reject); return nil
            case "u": self.state.flagSelection(nil); return nil
            default: break
            }
            switch event.keyCode {
            case 49:            // spazio
                self.toggleQuickLook(); return nil
            case 51, 117:       // ⌫ e canc
                self.state.deleteSelection(); return nil
            case 53:            // esc
                if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared().isVisible {
                    QLPreviewPanel.shared().orderOut(nil)
                } else {
                    self.state.selectNone()
                }
                return nil
            default:
                return event
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                               object: nil, queue: .main) { _ in
            Task { @MainActor in AppState.shared.optionHeld = false }
        }

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { note in
            guard let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            Task { @MainActor in AppState.shared.volumeMounted(url, showWindow: true) }
        }
        center.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main) { note in
            guard let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            Task { @MainActor in AppState.shared.volumeUnmounted(url) }
        }

        // Schede già inserite all'avvio
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil,
                                                            options: [.skipHiddenVolumes]) ?? []
        for url in volumes where url.path != "/" {
            state.volumeMounted(url, showWindow: true)
        }
        state.restoreLastFolder()

        if !launchedInBackground { showWindow() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard state.progress != nil else { return .terminateNow }
        let a = NSAlert()
        a.messageText = "È in corso un'importazione"
        a.informativeText = "Se esci adesso, la clip che si sta copiando non verrà salvata."
        a.addButton(withTitle: "Continua a importare")
        a.addButton(withTitle: "Interrompi ed esci")
        if a.runModal() == .alertSecondButtonReturn {
            state.cancelImport()
            return .terminateNow
        }
        return .terminateCancel
    }

    // MARK: - Finestra

    func showWindow() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 740),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
            w.title = "Clip Importer"
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 980, height: 560)
            w.contentView = NSHostingView(rootView: ContentView().environmentObject(state))
            w.center()
            w.setFrameAutosaveName("ClipImporterMainWindow")
            w.delegate = self
            window = w
        }
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        // Senza finestra l'app torna a vivere solo nella barra dei menu
        NSApp.setActivationPolicy(.accessory)
    }

    // MARK: - Barra dei menu (icona in alto)

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let image = NSImage(systemSymbolName: "sdcard", accessibilityDescription: "Clip Importer")
        image?.isTemplate = true
        item.button?.image = image
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusItem?.menu else { return }
        menu.removeAllItems()

        add(menu, "Apri Clip Importer", #selector(openWindowAction))
        if let p = state.progress {
            let item = NSMenuItem(title: "Importazione in corso: \(Int(p.fraction * 100))%", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let cards = state.sources.filter(\.isVolume)
        if cards.isEmpty {
            let item = NSMenuItem(title: "Nessuna scheda inserita", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        for card in cards {
            let item = add(menu, "Mostra le clip di «\(card.name)»", #selector(openCardAction(_:)))
            item.representedObject = card.id
            item.image = NSImage(systemSymbolName: "sdcard", accessibilityDescription: nil)
        }
        let folders = state.sources.filter { !$0.isVolume }
        for folder in folders {
            let item = add(menu, "Mostra le clip di «\(folder.name)»", #selector(openCardAction(_:)))
            item.representedObject = folder.id
            item.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
            item.toolTip = folder.id.path
            if state.current?.id == folder.id { item.state = .on }
        }
        add(menu, folders.isEmpty ? "Sfoglia una cartella…" : "Sfoglia un'altra cartella…", #selector(chooseFolderAction))
        menu.addItem(.separator())

        add(menu, "Apri quando inserisci una scheda", #selector(toggleAutoOpen)).state = state.autoOpen ? .on : .off
        add(menu, "Avvia all'accesso al Mac", #selector(toggleLogin)).state = state.launchAtLogin ? .on : .off
        menu.addItem(.separator())
        add(menu, "Esci da Clip Importer", #selector(NSApplication.terminate(_:)), target: NSApp)
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, key: String = "",
                     modifiers: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = target ?? self
        menu.addItem(item)
        return item
    }

    @objc private func openWindowAction() { showWindow() }
    @objc private func chooseFolderAction() { state.chooseSourceFolder() }
    @objc private func toggleAutoOpen() { state.autoOpen.toggle() }
    @objc private func toggleLogin() { state.launchAtLogin.toggle() }
    @objc private func openCardAction(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL,
           let source = state.sources.first(where: { $0.id == url }) {
            if state.progress == nil { state.open(source) }
            showWindow()
        }
    }

    // MARK: - Menu principale

    private func buildMainMenu() {
        let main = NSMenu()

        let appMenu = NSMenu()
        add(appMenu, "Informazioni su Clip Importer",
            #selector(NSApplication.orderFrontStandardAboutPanel(_:)), target: NSApp)
        appMenu.addItem(.separator())
        add(appMenu, "Nascondi Clip Importer", #selector(NSApplication.hide(_:)), key: "h", target: NSApp)
        appMenu.addItem(.separator())
        add(appMenu, "Esci da Clip Importer", #selector(NSApplication.terminate(_:)), key: "q", target: NSApp)
        addSubmenu(main, "Clip Importer", appMenu)

        let fileMenu = NSMenu(title: "Archivio")
        add(fileMenu, "Sfoglia una cartella…", #selector(chooseFolderAction), key: "o")
        add(fileMenu, "Aggiorna", #selector(refreshAction), key: "r")
        add(fileMenu, "Importa", #selector(importAction), key: "i")
        add(fileMenu, "Importa e cancella dalla scheda", #selector(moveAction), key: "i", modifiers: [.command, .option])
        fileMenu.addItem(.separator())
        add(fileMenu, "Anteprima rapida", #selector(quickLookAction), key: "y")
        add(fileMenu, "Mostra nel Finder", #selector(revealSelectionAction), key: "r", modifiers: [.command, .option])
        add(fileMenu, "Elimina", #selector(deleteAction), key: "\u{8}")
        add(fileMenu, "Espelli scheda", #selector(ejectAction), key: "e")
        fileMenu.addItem(.separator())
        let close = NSMenuItem(title: "Chiudi finestra", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenu.addItem(close)
        addSubmenu(main, "Archivio", fileMenu)

        let editMenu = NSMenu(title: "Modifica")
        editMenu.addItem(NSMenuItem(title: "Taglia", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        add(editMenu, "Copia", #selector(copyAction(_:)), key: "c")
        editMenu.addItem(NSMenuItem(title: "Incolla", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(.separator())
        add(editMenu, "Seleziona tutto", #selector(selectAllAction(_:)), key: "a")
        add(editMenu, "Seleziona solo le nuove", #selector(selectNewAction), key: "a", modifiers: [.command, .shift])
        add(editMenu, "Deseleziona tutto", #selector(selectNoneAction), key: "a", modifiers: [.command, .option])
        addSubmenu(main, "Modifica", editMenu)

        let flagMenu = NSMenu(title: "Etichette")
        add(flagMenu, "Segna come scelta ✔️  (P)", #selector(pickAction))
        add(flagMenu, "Segna come scartata ✖️  (X)", #selector(rejectAction))
        add(flagMenu, "Togli etichetta  (U)", #selector(unflagAction))
        flagMenu.addItem(.separator())
        add(flagMenu, "Seleziona le scelte", #selector(selectPicksAction))
        add(flagMenu, "Seleziona le scartate", #selector(selectRejectsAction))
        flagMenu.addItem(.separator())
        add(flagMenu, "Elimina le scartate dalla scheda…", #selector(deleteRejectedAction), key: "\u{8}", modifiers: [.command, .option])
        addSubmenu(main, "Etichette", flagMenu)

        let windowMenu = NSMenu(title: "Finestra")
        windowMenu.addItem(NSMenuItem(title: "Contrai", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        addSubmenu(main, "Finestra", windowMenu)
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = main
    }

    private func addSubmenu(_ main: NSMenu, _ title: String, _ submenu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        main.addItem(item)
    }

    @objc private func copyAction(_ sender: Any?) {
        // In un campo di testo ⌘C copia il testo; sulla griglia copia i file
        if let text = NSApp.keyWindow?.firstResponder as? NSText { text.copy(sender) } else { state.copySelection() }
    }
    @objc private func deleteAction() { state.deleteSelection() }
    @objc private func pickAction() { state.flagSelection(.pick) }
    @objc private func rejectAction() { state.flagSelection(.reject) }
    @objc private func unflagAction() { state.flagSelection(nil) }
    @objc private func selectPicksAction() { state.selectFlagged(.pick) }
    @objc private func selectRejectsAction() { state.selectFlagged(.reject) }
    @objc private func deleteRejectedAction() { state.deleteRejected() }
    @objc private func quickLookAction() { toggleQuickLook() }
    @objc private func revealSelectionAction() {
        let urls = state.selectedClips.map(\.url)
        if urls.isEmpty { state.revealCurrent() } else { NSWorkspace.shared.activateFileViewerSelecting(urls) }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        let inText = NSApp.keyWindow?.firstResponder is NSText
        switch item.action {
        case #selector(deleteAction):
            let place = (state.current?.isVolume ?? true) ? "Elimina dalla scheda" : "Sposta nel Cestino"
            let n = state.selectedClips.count
            item.title = n > 1 ? "\(place) (\(n))" : place
            return n > 0 && state.progress == nil && !inText
        case #selector(copyAction(_:)):
            return inText || !state.selection.isEmpty
        case #selector(pickAction), #selector(rejectAction), #selector(unflagAction):
            return !state.selection.isEmpty
        case #selector(deleteRejectedAction):
            item.title = (state.current?.isVolume ?? true) ? "Elimina le scartate dalla scheda…" : "Sposta le scartate nel Cestino"
            return state.rejectedCount > 0 && state.progress == nil
        case #selector(quickLookAction):
            return !state.selection.isEmpty
        case #selector(importAction), #selector(moveAction):
            return state.progress == nil && !state.clipsToImport.isEmpty
        default:
            return true
        }
    }

    // MARK: - Anteprima rapida (spazio / ⌘Y)

    private var previewItems: [URL] = []

    func toggleQuickLook() {
        let panel = QLPreviewPanel.shared()!
        if QLPreviewPanel.sharedPreviewPanelExists() && panel.isVisible {
            panel.orderOut(nil)
            return
        }
        previewItems = state.selectedClips.map(\.url)
        guard !previewItems.isEmpty else { NSSound.beep(); return }
        panel.makeKeyAndOrderFront(nil)
        if panel.dataSource == nil { panel.dataSource = self; panel.delegate = self }
        panel.reloadData()
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.delegate = self
    }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }
    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { previewItems.count }
    }
    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        MainActor.assumeIsolated { previewItems[index] as NSURL }
    }

    @objc private func importAction() { state.importClips(state.clipsToImport, move: state.deleteAfter) }
    @objc private func moveAction() { state.startMove() }
    @objc private func refreshAction() { state.refresh() }
    @objc private func ejectAction() { state.eject() }
    @objc private func selectNewAction() { state.selectNew() }
    @objc private func selectNoneAction() { state.selectNone() }
    @objc private func selectAllAction(_ sender: Any?) {
        // Se stai scrivendo in un campo di testo, ⌘A seleziona il testo
        if let text = NSApp.keyWindow?.firstResponder as? NSText {
            text.selectAll(sender)
        } else {
            state.selectAll()
        }
    }
}
