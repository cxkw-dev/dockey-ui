import SwiftUI

/// Only views that actually present live metrics opt into the engine stats stream.
struct DockeyMetricsVisibilityKey: PreferenceKey {
    static var defaultValue: Bool { false }

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}
