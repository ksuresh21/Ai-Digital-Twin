import AppKit

// AiTwin has no @main App struct on purpose.
//
// A SwiftUI `App` wants a window scene, and AiTwin's whole point is that it has
// no window in the ordinary sense -- just a borderless panel and a menu bar
// item. Driving `NSApplication` directly gives full control over the activation
// policy and the window level, which is exactly what a desktop companion needs.
//
// `MainActor.assumeIsolated` is correct rather than a workaround: top-level code
// in main.swift already runs on the main thread, but the compiler cannot infer
// that, so we state it once here instead of scattering isolation annotations.
MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    // Held for the process lifetime: NSApplication's delegate property is weak.
    objc_setAssociatedObject(application, "aitwin.delegate", delegate, .OBJC_ASSOCIATION_RETAIN)
    application.run()
}
