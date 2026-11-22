// Motion preferences, ported from `app/lib/app/motion.dart`: "Reduce motion"
// keeps fades but drops movement.

import SwiftUI
import FlashcardsCore

struct ReducedMotionKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether movement should be dropped, from the app setting or the device.
    var reducedMotion: Bool {
        get { self[ReducedMotionKey.self] }
        set { self[ReducedMotionKey.self] = newValue }
    }
}

/// The app's motion setting resolved against the device's Reduce Motion.
func reducedMotion(_ preference: MotionPreference, system: Bool) -> Bool {
    switch preference {
    case .reduce: true
    case .full: false
    case .system: system
    }
}

/// A transition that slides unless motion is reduced, when it only fades.
func slideOrFade(_ edge: Edge, reduced: Bool) -> AnyTransition {
    reduced ? .opacity : .move(edge: edge).combined(with: .opacity)
}
