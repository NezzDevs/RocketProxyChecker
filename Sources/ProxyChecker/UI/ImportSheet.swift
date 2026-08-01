import SwiftUI

struct ImportSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var validCount = 0
    @State private var duplicateCount = 0
    @State private var skippedCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(
                title: "Add proxies",
                subtitle: "One per line. host:port, host:port:user:pass, user:pass@host:port and scheme:// all work."
            )

            TextEditor(text: $text)
                .font(.mono(12))
                .scrollContentBackground(.hidden)
                .background(Theme.panel)
                .padding(14)
                .onChange(of: text) { _, newValue in
                    let result = ProxyParser.parse(newValue)
                    validCount = result.rows.count
                    duplicateCount = result.duplicates
                    skippedCount = result.skipped
                }

            Divider().overlay(Theme.hairline)

            HStack(spacing: 10) {
                Text(text.isEmpty
                     ? "Nothing pasted yet"
                     : "\(validCount) valid · \(duplicateCount) duplicate · \(skippedCount) unreadable")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)

                Spacer()

                Button("Cancel") { dismiss() }
                    .buttonStyle(BarButtonStyle())

                Button("Add \(validCount)") {
                    model.importText(text)
                    dismiss()
                }
                .buttonStyle(BarButtonStyle(prominent: true))
                .keyboardShortcut(.defaultAction)
                .disabled(validCount == 0)
            }
            .padding(16)
        }
        .frame(width: 620, height: 520)
        .background(Theme.background)
    }
}
