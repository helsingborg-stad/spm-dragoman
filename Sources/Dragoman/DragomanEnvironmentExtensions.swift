//
//  File.swift
//  
//
//  Created by Tomas Green on 2021-06-23.
//

import SwiftUI
import Combine

private struct DragomanBundleKey: EnvironmentKey {
    static let defaultValue: Bundle = .main
}

public extension EnvironmentValues {
    var dragomanBundle: Bundle {
        get { self[DragomanBundleKey.self] }
        set { self[DragomanBundleKey.self] = newValue }
    }
}

public extension View {
    func dragomenBundle(_ value: Bundle) -> some View {
        environment(\.dragomanBundle, value)
    }
}
public struct ATText: View {
    @Environment(\.dragomanBundle) var bundle
    var text: LocalizedStringKey
    public init(_ text:LocalizedStringKey) {
        self.text = text
    }
    public var body: some View {
        Text(text, bundle: bundle).autoUpdate()
    }
}
