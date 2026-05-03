//
//  View+KeyboardDismiss.swift
//  InZentory
//

import SwiftUI

extension View {
    /// Adds a "Done" button to the keyboard toolbar that dismisses any active text field,
    /// regardless of whether it has a @FocusState binding.
    func keyboardDoneButton() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { UIApplication.dismissKeyboard() }
            }
        }
    }
}

extension UIApplication {
    /// Resigns first responder on whatever is currently focused — works for any UITextField/UITextView.
    static func dismissKeyboard() {
        shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
