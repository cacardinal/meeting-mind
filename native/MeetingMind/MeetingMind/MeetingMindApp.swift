//
//  MeetingMindApp.swift
//  MeetingMind
//
//  Created by Chris Cardinal on 2/3/26.
//

import SwiftUI
import AppKit
import Combine

@main
struct MeetingMindApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appDelegate.windowManager)
        }
        .windowBackgroundDragBehavior(.enabled)
    }
}

/// Manages window state and overlay mode
class WindowManager: ObservableObject {
    @Published var isOverlayMode = false
    @Published var isInvisibleToScreenShare = false

    weak var mainWindow: NSWindow?

    func toggleOverlayMode() {
        isOverlayMode.toggle()
        updateWindowLevel()
    }

    func toggleInvisibleMode() {
        isInvisibleToScreenShare.toggle()
        updateSharingType()
    }

    func enableInterviewMode() {
        isOverlayMode = true
        isInvisibleToScreenShare = true
        updateWindowLevel()
        updateSharingType()
    }

    func disableInterviewMode() {
        isOverlayMode = false
        isInvisibleToScreenShare = false
        updateWindowLevel()
        updateSharingType()
    }

    private func updateWindowLevel() {
        guard let window = mainWindow else { return }
        window.level = isOverlayMode ? .floating : .normal
        window.collectionBehavior = isOverlayMode
            ? [.canJoinAllSpaces, .fullScreenAuxiliary]
            : [.managed]
    }

    private func updateSharingType() {
        guard let window = mainWindow else { return }
        // .none = invisible to screen share/recording
        // .readOnly = visible but not interactive in screen share
        window.sharingType = isInvisibleToScreenShare ? .none : .readWrite
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    let windowManager = WindowManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Get the main window after a brief delay to ensure it's created
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let window = NSApplication.shared.windows.first {
                self.windowManager.mainWindow = window

                // Set initial window properties
                window.titlebarAppearsTransparent = true
                window.isMovableByWindowBackground = true

                // Enable transparency (frosted glass effect)
                window.isOpaque = false
                window.backgroundColor = NSColor.clear
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

// MARK: - Visual Effect View (Frosted Glass)

/// NSVisualEffectView wrapper for SwiftUI - provides frosted glass background
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    init(material: NSVisualEffectView.Material = .hudWindow, blendingMode: NSVisualEffectView.BlendingMode = .behindWindow) {
        self.material = material
        self.blendingMode = blendingMode
    }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
