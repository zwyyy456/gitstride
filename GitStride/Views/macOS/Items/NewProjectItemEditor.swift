import SwiftUI

#if os(macOS)
struct NewProjectItemEditor: View {
    let store: ProjectStore
    let project: Project?
    let repositories: [String]
    @Binding var draft: NewProjectItemDraft
    @Binding var validationMessage: String?
    let statusOptions: [String]
    let priorityOptions: [String]
    let reviewQuickEntry: () -> Void

    @State private var showsQuickEntryHelp = false
    @FocusState private var focusedField: Field?
    private enum Field { case title, quickEntry }
    private static let horizontalPadding = AddProjectItemView.horizontalPadding
    private static let fieldSpacing: CGFloat = 12

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if draft.usesQuickEntry {
                    quickEntryForm
                } else {
                    createForm
                }

                if draft.usesQuickEntry == false, let message = validationMessage {
                    validationNotice(message)
                }
            }
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Self.horizontalPadding)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .defaultScrollAnchor(.top)
        .scrollBounceBehavior(.basedOnSize)
        .onAppear { focusEditor() }
        .onChange(of: draft.usesQuickEntry) { _, _ in
            validationMessage = nil
            focusEditor()
        }
        .onChange(of: draft.quickEntry) { _, _ in
            if draft.usesQuickEntry { validationMessage = nil }
        }
    }

    private var createForm: some View {
        Grid(alignment: .leading, horizontalSpacing: Self.fieldSpacing, verticalSpacing: 14) {
            if draft.itemType == .issue {
                GridRow(alignment: .firstTextBaseline) {
                    fieldLabel(String(localized: "Repository"))
                    VStack(alignment: .leading, spacing: 6) {
                        RepositoryComboBox(
                            text: $draft.repository,
                            repositories: repositories
                        )
                        if let message = draft.repositoryValidationMessage {
                            validationNotice(message)
                        }
                    }
                }
            }

            GridRow(alignment: .firstTextBaseline) {
                fieldLabel(String(localized: "Type"))
                Picker("Type", selection: $draft.itemType) {
                    ForEach(NewProjectItemDraft.ItemType.allCases) { type in
                        Text(type.title).tag(type)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GridRow(alignment: .firstTextBaseline) {
                fieldLabel(String(localized: "Title"))
                TextField(draft.itemType == .issue ? String(localized: "Issue title") : String(localized: "Draft title"), text: $draft.title)
                    .accessibilityLabel("Title, required")
                    .focused($focusedField, equals: .title)
            }

            GridRow(alignment: .top) {
                VStack(alignment: .trailing, spacing: 2) {
                    fieldLabel(String(localized: "Description"))
                    Text("Optional")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                TextField("Description", text: $draft.bodyText, axis: .vertical)
                    .lineLimit(4...6)
                    .accessibilityLabel("Description, optional")
            }

            if draft.itemType == .issue {
                GridRow(alignment: .firstTextBaseline) {
                    fieldLabel(String(localized: "Labels"))
                    LabelTokenField(text: $draft.labels, suggestions: labelSuggestions)
                }

                GridRow(alignment: .firstTextBaseline) {
                    fieldLabel(String(localized: "Assignees"))
                    HStack(alignment: .firstTextBaseline, spacing: Self.fieldSpacing) {
                        TextField("\(store.currentUserLogin ?? "username"), @me", text: $draft.assignees)
                            .accessibilityLabel("Assignees")
                            .accessibilityHint("Separate usernames with commas. Use @me for yourself.")
                            .help("Separate usernames with commas. Use @me for yourself.")
                            .frame(maxWidth: .infinity)

                        Button("Assign to me") {
                            draft.assignToMe()
                        }
                        .buttonStyle(.link)
                        .fixedSize()
                        .disabled(draft.hasCurrentUserAssignee(currentUser: store.currentUserLogin))
                    }
                }

                Divider()
                    .gridCellColumns(2)
                    .padding(.vertical, 4)

                if statusOptions.isEmpty == false {
                    GridRow(alignment: .firstTextBaseline) {
                        fieldLabel(String(localized: "Status"))
                        statusPicker
                    }
                }

                if priorityOptions.isEmpty == false {
                    GridRow(alignment: .firstTextBaseline) {
                        fieldLabel(String(localized: "Priority"))
                        priorityPicker.labelsHidden()
                    }
                }
                dateRow("Start date", selection: $draft.startDate)
                dateRow("Target date", selection: $draft.targetDate)
                GridRow {
                    Color.clear.frame(width: 0, height: 0)
                    Text("Missing date fields are created only when you submit a date.")
                        .font(.caption).foregroundStyle(.secondary)
                }

            }
        }
        .pickerStyle(.menu)
    }

    private func fieldLabel(_ labelTitle: String) -> some View {
        Text(labelTitle)
            .fixedSize()
            .gridColumnAlignment(.trailing)
    }

    private func dateRow(_ title: LocalizedStringKey, selection: Binding<Date?>) -> some View {
        GridRow(alignment: .firstTextBaseline) {
            Text(title)
                .fixedSize()
                .gridColumnAlignment(.trailing)
            HStack {
                if let date = selection.wrappedValue {
                    DatePicker(title, selection: Binding(
                        get: { selection.wrappedValue ?? date },
                        set: { selection.wrappedValue = $0 }
                    ), displayedComponents: .date)
                    .labelsHidden()
                    .fixedSize()
                    Button("Clear", systemImage: "xmark.circle.fill") {
                        selection.wrappedValue = nil
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text("Clear") + Text(" ") + Text(title))
                } else {
                    Text("Not set")
                        .foregroundStyle(.secondary)
                    Button("Set date…") { selection.wrappedValue = Date() }
                }
            }
        }
    }

    private var statusPicker: some View {
        Picker("Status", selection: $draft.status) {
            if draft.status.isEmpty {
                Text("Choose Status").tag("").disabled(true)
            }
            ForEach(statusOptions, id: \.self) { option in
                Text(option).tag(option)
            }
        }
        .labelsHidden()
        .accessibilityLabel("Status, required")
        .help(draft.status.isEmpty ? String(localized: "Choose Status") : draft.status)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var priorityPicker: some View {
        Picker("Priority", selection: $draft.priority) {
            Text("Not set").tag("")
            ForEach(priorityOptions, id: \.self) { option in
                Text(option).tag(option)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var labelSuggestions: [String] {
        let items = project?.items ?? []
        return Array(Set(items.filter {
            $0.repositoryName?.caseInsensitiveCompare(draft.repository.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
        }.flatMap { $0.labels.map(\.name) })).sorted()
    }

    private var quickEntryForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Describe the item")
                .font(.subheadline)

            TextField("Title and qualifiers", text: $draft.quickEntry)
                .accessibilityLabel("Quick Entry")
                .focused($focusedField, equals: .quickEntry)
                .onSubmit(reviewQuickEntry)

            if let message = validationMessage {
                validationNotice(message)
            }

            Text("Example: Fix login @me #bug")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Review the details before creating the item.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Syntax Help", systemImage: "questionmark.circle") {
                showsQuickEntryHelp = true
            }
            .buttonStyle(.link)
            .font(.caption)
            .popover(isPresented: $showsQuickEntryHelp) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quick Entry Syntax")
                        .font(.headline)
                    Text("Start with a title, then add any of these qualifiers:")
                    Text("repo:owner/repo\nstatus:Todo\npriority:High\n@me or @username\n#bug")
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                    Text(
                        "Use the status and priority names from your project. For names with spaces, select the value in the full form instead."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(16)
                .frame(width: 300)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func validationNotice(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    private func focusEditor() {
        focusedField = draft.usesQuickEntry ? .quickEntry : .title
    }
}

#endif
