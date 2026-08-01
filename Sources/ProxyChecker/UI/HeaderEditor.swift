import SwiftUI

struct HeaderEditor: View {
    @Binding var headers: [HTTPHeader]

    private static let suggestions: [(name: String, value: String)] = [
        ("Referer", "https://www.google.com/"),
        ("Origin", "https://www.google.com"),
        ("Accept-Language", "en-US,en;q=0.9"),
        ("Accept-Encoding", "gzip, deflate"),
        ("X-Requested-With", "XMLHttpRequest"),
        ("Cache-Control", "no-cache"),
        ("Cookie", "")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if headers.isEmpty {
                Text("No extra headers. The check sends only User-Agent, Accept and Connection.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textFaint)
                    .padding(.bottom, 2)
            } else {
                ForEach($headers) { $header in
                    row($header)
                }
            }

            HStack(spacing: 8) {
                Button {
                    headers.append(HTTPHeader())
                } label: {
                    Label("Add header", systemImage: "plus")
                }
                .buttonStyle(BarButtonStyle())

                Menu("Common…") {
                    ForEach(Self.suggestions, id: \.name) { suggestion in
                        Button(suggestion.name) {
                            add(name: suggestion.name, value: suggestion.value)
                        }
                    }
                }
                .menuStyle(.button)
                .buttonStyle(BarButtonStyle())
                .fixedSize()
            }
        }
    }

    @ViewBuilder
    private func row(_ header: Binding<HTTPHeader>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                Toggle("", isOn: header.enabled)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .help("Send this header")

                FieldBox {
                    TextField("Name", text: header.name)
                        .textFieldStyle(.plain)
                        .font(.mono(11.5))
                }
                .frame(width: 150)

                FieldBox {
                    TextField("Value", text: header.value)
                        .textFieldStyle(.plain)
                        .font(.mono(11.5))
                }

                Button {
                    headers.removeAll { $0.id == header.wrappedValue.id }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.03))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.hairline, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help("Remove")
            }
            .opacity(header.wrappedValue.enabled ? 1 : 0.45)

            if header.wrappedValue.isReserved {
                Text("URLSession sets this header itself and will ignore this value.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.slow)
                    .padding(.leading, 26)
            }
        }
    }

    private func add(name: String, value: String) {

        if let index = headers.firstIndex(where: {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        }) {
            headers[index].value = value
            headers[index].enabled = true
        } else {
            headers.append(HTTPHeader(name: name, value: value))
        }
    }
}
