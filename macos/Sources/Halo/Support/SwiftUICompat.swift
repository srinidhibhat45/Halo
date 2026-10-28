import SwiftUI

/// SwiftUI's `@State`.
///
/// In the macOS 27 SDK `@State` is a macro whose compiler plugin ships only with Xcode, so it
/// does not compile with the Command Line Tools. The property wrapper type itself still exists,
/// and naming it through a typealias bypasses the macro. Use `@ViewState` wherever you would
/// write `@State`. (`@Binding`, `@Environment`, `@FocusState`, `@AppStorage`, `@Bindable` and
/// `@Observable` are unaffected. Avoid `#Preview`, `@Entry` and `@Animatable`: also macros.)
typealias ViewState<Value> = SwiftUI.State<Value>
