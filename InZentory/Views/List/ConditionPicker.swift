//
//  ConditionPicker.swift
//  InZentory
//

import SwiftUI

struct ConditionPicker: View {
    @Binding var selection: ItemCondition?
    var cases: [ItemCondition] = ItemCondition.storiesCases
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(cases.enumerated()), id: \.element) { index, cond in
                Button {
                    selection = (selection == cond) ? nil : cond
                } label: {
                    let useShort = cases.count > 4
                    Text(useShort ? cond.shortName : cond.displayName)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(
                            selection == cond ? tint : Color.clear
                        )
                        .foregroundStyle(selection == cond ? .white : .primary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.15), value: selection)

                if index < cases.count - 1 {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(width: 0.5, height: 36)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
        )
    }
}

#Preview {
    struct PreviewHelper: View {
        @State var cond1: ItemCondition? = .veryGood
        @State var cond2: ItemCondition? = .good
        var body: some View {
            VStack(spacing: 20) {
                ConditionPicker(selection: $cond1)
                    .padding()
                ConditionPicker(selection: $cond2, cases: ItemCondition.surplusCases, tint: .hotPink)
                    .padding()
            }
        }
    }
    return PreviewHelper()
}
