import SwiftUI

struct ProjectFieldEditor: View {
    let field: ProjectField
    let value: ProjectFieldValue?
    let isEditable: Bool
    let update: (ProjectFieldValue?) async throws -> Void

    @State private var draftValue = ""
    @State private var draftDate = RoadmapCalendar.today
    @State private var isEditing = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var textFocused: Bool

    var body: some View {
        LabeledContent {
            VStack(alignment: .trailing, spacing: 6) {
                editor
                if isSaving {
                    ProgressView().controlSize(.mini).accessibilityLabel("Saving field")
                }
                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Couldn’t save field: \(errorMessage)")
                }
            }
        } label: {
            Text(field.name).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var editor: some View {
        switch field.kind {
        case .singleSelect:
            Picker(
                field.name,
                selection: Binding<String?>(
                    get: { if case .singleSelect(let id, _) = value { id } else { nil } },
                    set: { id in
                        set(
                            id.flatMap { id in field.options.first { $0.id == id } }
                                .map { .singleSelect(optionId: $0.id, name: $0.name) })
                    }
                )
            ) {
                Text("Not Set").tag(String?.none)
                ForEach(field.options) { Text($0.name).tag(Optional($0.id)) }
            }
            .labelsHidden().pickerStyle(.menu).disabled(!isEditable || isSaving)

        case .iteration:
            Picker(
                field.name,
                selection: Binding<String?>(
                    get: { if case .iteration(let id, _) = value { id } else { nil } },
                    set: { id in
                        set(
                            id.flatMap { id in field.iterations.first { $0.id == id } }
                                .map { .iteration(id: $0.id, title: $0.title) })
                    }
                )
            ) {
                Text("Not Set").tag(String?.none)
                ForEach(field.iterations) { Text($0.title).tag(Optional($0.id)) }
            }
            .labelsHidden().pickerStyle(.menu).disabled(!isEditable || isSaving)

        case .date:
            valueButton
                .popover(isPresented: $isEditing) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(field.name).font(.headline)
                        DatePicker(field.name, selection: $draftDate, displayedComponents: .date)
                            .datePickerStyle(.graphical).labelsHidden()
                            .environment(\.calendar, RoadmapCalendar.calendar)
                            .environment(\.timeZone, RoadmapCalendar.calendar.timeZone)
                            .disabled(isSaving)
                        if let errorMessage {
                            Text(errorMessage).font(.caption).foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        HStack {
                            if value != nil { Button("Clear field") { set(nil) }.disabled(isSaving) }
                            Spacer()
                            Button("Cancel", role: .cancel) { isEditing = false }
                                .keyboardShortcut(.cancelAction).disabled(isSaving)
                            Button("Done") { set(.date(dateString(draftDate))) }
                                .keyboardShortcut(.defaultAction).disabled(isSaving)
                        }
                    }
                    .padding(16)
                    .frame(width: 300)
                }

        case .number, .text:
            if isEditing {
                VStack(alignment: .trailing, spacing: 6) {
                    TextField(field.name, text: $draftValue)
                        .textFieldStyle(.roundedBorder)
                        .focused($textFocused)
                        .onSubmit(saveDraft)
                        #if os(macOS)
                        .onExitCommand { if !isSaving { isEditing = false } }
                        #endif
                        .disabled(isSaving)
                    if invalidNumber {
                        Text("Enter a valid number.").font(.caption).foregroundStyle(.red)
                    }
                    HStack {
                        Button("Cancel") { isEditing = false }.disabled(isSaving)
                        Button("Save", action: saveDraft).disabled(isSaving || invalidNumber)
                    }
                }
            } else {
                valueButton
            }

        case .unsupported:
            Text(displayValue).foregroundStyle(.secondary)
        }
    }

    private var valueButton: some View {
        Button {
            errorMessage = nil
            if case .number(let number) = value {
                draftValue = String(number)
            } else if case .text(let text) = value {
                draftValue = text
            } else {
                draftValue = ""
            }
            if case .date(let raw) = value, let date = RoadmapCalendar.date(raw) {
                draftDate = date
            } else {
                draftDate = RoadmapCalendar.today
            }
            isEditing = true
            textFocused = true
        } label: {
            Text(displayValue)
                .foregroundStyle(value == nil ? .secondary : .primary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.borderless)
        .disabled(!isEditable || isSaving)
        .accessibilityLabel("\(field.name): \(displayValue)")
        .accessibilityHint(isEditable ? String(localized: "Edit field") : String(localized: "Read-only"))
    }

    private var displayValue: String {
        switch value {
        case .singleSelect(_, let name): name
        case .iteration(_, let title): title
        case .date(let raw): RoadmapCalendar.date(raw).map(RoadmapCalendar.label) ?? raw
        case .number(let number): number.formatted()
        case .text(let text): text
        case nil: String(localized: "Not Set")
        }
    }

    private var invalidNumber: Bool {
        let text = draftValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return field.kind == .number && !text.isEmpty && Double(text).map { !$0.isFinite } != false
    }

    private func saveDraft() {
        guard !invalidNumber else { return }
        let text = draftValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            set(nil)
        } else if field.kind == .number, let number = Double(text) {
            set(.number(number))
        } else if field.kind == .text {
            set(.text(text))
        }
    }

    private func dateString(_ date: Date) -> String {
        let parts = RoadmapCalendar.calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    private func set(_ proposedValue: ProjectFieldValue?) {
        guard isEditable, !isSaving else { return }
        guard proposedValue != value else {
            isEditing = false
            return
        }
        isSaving = true
        errorMessage = nil
        Task { @MainActor in
            defer { isSaving = false }
            do {
                try await update(proposedValue)
                isEditing = false
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
