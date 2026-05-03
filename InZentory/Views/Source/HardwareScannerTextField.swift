//
//  HardwareScannerTextField.swift
//  InZentory
//
//  A UITextField wrapper that stays first responder without showing the software
//  keyboard (inputView = UIView()). Tapping the keyboard toggle button switches
//  inputView to nil so the software keyboard appears for manual entry.
//  Hardware barcode scanners (which act as Bluetooth keyboards) send characters
//  directly to the first responder, so this field captures their output silently.
//

#if os(iOS)
import SwiftUI
import UIKit

struct HardwareScannerTextField: UIViewRepresentable {
    @Binding var text: String
    /// When true, shows the software keyboard (manual entry). When false,
    /// hardware scanner mode — first responder with no visible keyboard.
    var showKeyboard: Bool
    var onSubmit: () -> Void

    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField()
        tf.delegate = context.coordinator
        tf.placeholder = "Tap to activate hardware scanner"
        tf.autocorrectionType = .no
        tf.autocapitalizationType = .none
        tf.spellCheckingType = .no
        tf.returnKeyType = .search
        tf.keyboardType = .numberPad
        tf.font = UIFont.monospacedSystemFont(ofSize: 15, weight: .regular)
        tf.borderStyle = .none
        tf.backgroundColor = .clear
        // Suppress software keyboard by default
        tf.inputView = UIView()
        // Number pad has no Return key — add a toolbar with a Submit button
        tf.inputAccessoryView = context.coordinator.makeAccessoryToolbar()
        context.coordinator.textField = tf
        return tf
    }

    func updateUIView(_ tf: UITextField, context: Context) {
        // Sync text (avoid infinite loop)
        if tf.text != text { tf.text = text }

        // Sync keyboard visibility
        let wantsKeyboard = showKeyboard
        let hasKeyboard   = (tf.inputView == nil)
        if wantsKeyboard != hasKeyboard {
            tf.inputView = wantsKeyboard ? nil : UIView()
            if tf.isFirstResponder { tf.reloadInputViews() }
        }

        // Keep coordinator callbacks current
        context.coordinator.onSubmit = onSubmit
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(binding: $text, onSubmit: onSubmit)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UITextFieldDelegate {
        var binding: Binding<String>
        var onSubmit: () -> Void
        weak var textField: UITextField?

        init(binding: Binding<String>, onSubmit: @escaping () -> Void) {
            self.binding  = binding
            self.onSubmit = onSubmit
        }

        func textField(
            _ tf: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            let current = tf.text ?? ""
            if let r = Range(range, in: current) {
                let newText = current.replacingCharacters(in: r, with: string)
                DispatchQueue.main.async { self.binding.wrappedValue = newText }
            }
            return true
        }

        func makeAccessoryToolbar() -> UIToolbar {
            let bar = UIToolbar()
            bar.sizeToFit()
            let spacer = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
            let submit = UIBarButtonItem(title: "Search", style: .prominent, target: self, action: #selector(handleSubmitTap))
            bar.items = [spacer, submit]
            return bar
        }

        @objc private func handleSubmitTap() {
            guard let tf = textField else { return }
            let trimmed = (tf.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            DispatchQueue.main.async { self.onSubmit() }
        }

        func textFieldShouldReturn(_ tf: UITextField) -> Bool {
            let trimmed = (tf.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            DispatchQueue.main.async { self.onSubmit() }
            return false
        }
    }
}
#endif
