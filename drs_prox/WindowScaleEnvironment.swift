import SwiftUI

private struct WindowScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

extension EnvironmentValues {
    var windowScale: CGFloat {
        get { self[WindowScaleKey.self] }
        set { self[WindowScaleKey.self] = newValue }
    }
}
