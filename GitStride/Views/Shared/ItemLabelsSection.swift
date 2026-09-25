import SwiftUI

struct ItemLabelsSection: View {
    let store: ProjectStore
    let item: ProjectItem
    @State private var localError: String?
    @State private var isSaving = false
    let projectID: String
    private var canEdit: Bool { store.canEditProject(id: projectID) }
    @State private var labelName = ""
    @State private var showsLabelPicker = false

    var body: some View {
        LabeledContent(String(localized: "Labels")) {
            VStack(alignment: .trailing, spacing: 8) {
                if item.labels.isEmpty {
                    if !canEdit { Text("No labels").foregroundStyle(.secondary) }
                } else {
                    ForEach(item.labels) { label in
                        HStack {
                            Circle()
                                .fill(Color(hex: label.color))
                                .frame(width: 9, height: 9)
                            Text(label.name).fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            if canEdit {
                                Button {
                                    guard !isSaving else { return }
                                    localError = nil
                                    isSaving = true
                                    Task { @MainActor in
                                        defer { isSaving = false }
                                        do {
                                            try await store.removeLabel(
                                                from: item,
                                                in: projectID,
                                                name: label.name
                                            )
                                        } catch {
                                            report(error)
                                        }
                                    }
                                } label: {
                                    Image(systemName: "xmark")
                                }
                                .buttonStyle(.borderless)
                                .help("Remove label")
                                .accessibilityLabel("Remove label")
                                .disabled(isSaving)
                            }
                        }
                    }
                }

                if canEdit {
                    Button(
                        item.labels.isEmpty ? String(localized: "No Labels…") : String(localized: "Add Label…"),
                        action: showLabelPicker
                    )
                    .buttonStyle(.borderless)
                    .disabled(isSaving)
                    .popover(isPresented: $showsLabelPicker) {
                        labelPicker(item)
                    }
                }
                if isSaving { ProgressView().controlSize(.mini).accessibilityLabel("Saving field") }
                if let localError { Text(localError).font(.caption).foregroundStyle(.red) }
            }
        }
    }

    private func labelPicker(_ item: ProjectItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Label")
                .font(.headline)

            TextField("Existing repository label", text: $labelName)
                .textFieldStyle(.roundedBorder)
                .onSubmit { addLabel(to: item) }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    showsLabelPicker = false
                }
                Button("Add Label") {
                    addLabel(to: item)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSaving || labelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let localError { Text(localError).font(.caption).foregroundStyle(.red).padding() }
            if isSaving { ProgressView().controlSize(.small).padding() }
        }
        .padding()
        .frame(width: 320)
    }

    private func showLabelPicker() {
        labelName = ""
        showsLabelPicker = true
    }

    private func addLabel(to item: ProjectItem) {
        let name = labelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.isEmpty == false else { return }
        guard !isSaving else { return }
        localError = nil
        isSaving = true
        Task { @MainActor in
            defer { isSaving = false }
            do {
                try await store.addLabel(to: item, in: projectID, name: name)
                labelName = ""
                showsLabelPicker = false
            } catch {
                report(error)
            }
        }
    }

    private func report(_ error: Error) {
        guard (error is CancellationError) == false else { return }
        localError = error.localizedDescription
    }
}

extension Color {
    fileprivate init(hex: String) {
        let value = UInt64(hex, radix: 16) ?? 0x808080
        self.init(
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255
        )
    }
}
