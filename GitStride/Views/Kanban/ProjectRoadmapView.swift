import SwiftUI

private struct RoadmapHorizontalOffset: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct RoadmapCommandContext {
    let zoom: Binding<RoadmapZoom>
    let today: () -> Void
    let showOptions: () -> Void
}

private struct RoadmapCommandKey: FocusedValueKey {
    typealias Value = RoadmapCommandContext
}

extension FocusedValues {
    var roadmapCommands: RoadmapCommandContext? {
        get { self[RoadmapCommandKey.self] }
        set { self[RoadmapCommandKey.self] = newValue }
    }
}

struct ProjectRoadmapView: View {
    let project: Project
    let items: [ProjectItem]
    @Bindable var store: ProjectStore
    @Binding var isSelecting: Bool
    @Binding var selectedItemIDs: Set<String>
    @Binding var currentItemID: String?
    @FocusState private var keyboardItemID: String?
    let showItemDetail: (ItemInspectorReference) -> Void
    let clearFilters: () -> Void
    let reportError: (Error) -> Void

    @AppStorage private var storedStartFieldID: String?
    @AppStorage private var storedEndFieldID: String?
    @AppStorage private var zoom: RoadmapZoom
    @AppStorage private var groupsByStatus: Bool
    @AppStorage private var titleWidth: Double
    @State private var showsOptions = false
    @State private var horizontalOffset: CGFloat = 0
    @State private var todayRequest = 0
    @State private var today = RoadmapCalendar.today
    @State private var timelineStart: Date?
    @State private var timelineEnd: Date?

    private struct Row: Identifiable {
        enum ID: Hashable { case group(String), item(String) }
        let id: ID
        let item: ProjectItem?
        let title: String
        let schedule: RoadmapSchedule?
        var height: CGFloat { item == nil ? 32 : 52 }
    }

    init(project: Project, items: [ProjectItem], store: ProjectStore, preferenceID: String,
         isSelecting: Binding<Bool>, selectedItemIDs: Binding<Set<String>>, currentItemID: Binding<String?>,
         showItemDetail: @escaping (ItemInspectorReference) -> Void,
         clearFilters: @escaping () -> Void, reportError: @escaping (Error) -> Void) {
        self.project = project
        self.items = items
        self.store = store
        _isSelecting = isSelecting
        _selectedItemIDs = selectedItemIDs
        _currentItemID = currentItemID
        self.showItemDetail = showItemDetail
        self.clearFilters = clearFilters
        self.reportError = reportError
        let preferences = ProjectDisplayPreferences(id: preferenceID)
        _storedStartFieldID = AppStorage(preferences.key(for: .roadmapStartField))
        _storedEndFieldID = AppStorage(preferences.key(for: .roadmapEndField))
        _zoom = AppStorage(wrappedValue: .quarter, preferences.key(for: .roadmapZoom))
        _groupsByStatus = AppStorage(wrappedValue: true, preferences.key(for: .roadmapGroupsByStatus))
        _titleWidth = AppStorage(wrappedValue: 300, preferences.key(for: .roadmapTitleWidth))
    }

    private var dateFields: [ProjectField] {
        project.fields.filter { $0.kind == .date || $0.kind == .iteration }
    }

    private var startFieldID: String {
        ProjectDisplayPreferences.roadmapFieldID(storedStartFieldID, defaultName: "Start date", fields: project.fields)
    }

    private var endFieldID: String {
        ProjectDisplayPreferences.roadmapFieldID(storedEndFieldID, defaultName: "Target date", fields: project.fields)
    }

    private var isConfigured: Bool { !startFieldID.isEmpty || !endFieldID.isEmpty }

    private var rows: [Row] {
        func row(_ item: ProjectItem) -> Row {
            Row(id: .item(item.id), item: item, title: item.displayTitle,
                schedule: .make(values: item.fieldValues, fields: project.fields,
                                startFieldID: startFieldID, endFieldID: endFieldID))
        }
        guard groupsByStatus else { return items.map(row) }
        let groups = Dictionary(grouping: items, by: { $0.statusOptionId ?? "" })
        let known = project.statusOptions.map(\.id)
        let keys = known.filter { groups[$0] != nil } + groups.keys.filter { !known.contains($0) }.sorted()
        return keys.flatMap { key -> [Row] in
            let members = groups[key] ?? []
            let name = project.statusOptions.first { $0.id == key }?.name
                ?? members.first?.status ?? String(localized: "No Status")
            return [Row(id: .group(key), item: nil, title: "\(name) · \(members.count)", schedule: nil)]
                + members.map(row)
        }
    }

    var body: some View {
        Group {
            if !isConfigured {
                ContentUnavailableView {
                    Label("Set Up Roadmap", systemImage: "calendar")
                } description: {
                    Text(dateFields.isEmpty
                         ? "Add a date or iteration field to this project on GitHub to schedule items."
                         : "Choose the fields used for start and target dates. Layout settings stay on this Mac.")
                } actions: {
                    if dateFields.isEmpty {
                        if let url = URL(string: project.url) { Link("Open in GitHub", destination: url) }
                    } else {
                        Button("Choose Date Fields") { showsOptions = true }
                    }
                }
            } else if items.isEmpty {
                ContentUnavailableView {
                    if project.items.isEmpty { Label("No items", systemImage: "tray") }
                    else { Label("No Matching Items", systemImage: "line.3.horizontal.decrease.circle") }
                } description: {
                    if project.items.isEmpty { Text("Items added to this GitHub Project will appear here.") }
                    else { Text("Try removing filters or changing your search.") }
                } actions: {
                    if !project.items.isEmpty { Button("Clear Filters", action: clearFilters) }
                }
            } else {
                GeometryReader { geometry in
                    timeline(rows, width: geometry.size.width)
                }
            }
        }
        .toolbar {
            ToolbarGroupBoundary(placement: .secondaryAction)
            ToolbarItem(placement: .secondaryAction) {
                Button("Today", action: goToToday)
                    .disabled(!isConfigured || items.isEmpty)
            }
            ToolbarGroupBoundary(placement: .secondaryAction)
            ToolbarItemGroup(placement: .secondaryAction) {
                Picker("Timeline Zoom", selection: $zoom) {
                    ForEach(RoadmapZoom.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .frame(width: 110)
                Button { showsOptions = true } label: {
                    Label("Roadmap Options", systemImage: "slider.horizontal.3")
                }
                .help("Roadmap Options")
            }
        }
        .focusedSceneValue(\.roadmapCommands, RoadmapCommandContext(
            zoom: $zoom, today: goToToday, showOptions: { showsOptions = true }
        ))
        .sheet(isPresented: $showsOptions) { options }
        .itemSelectionKeyboard(ids: rows.compactMap(\.item).filter { store.pendingCreationState(for: $0.id) == nil }.map(\.id), current: $currentItemID,
            selected: $selectedItemIDs, isSelecting: $isSelecting)
        .onChange(of: items.map(\.id)) { _, ids in selectedItemIDs.formIntersection(ids) }
        .onChange(of: rows.compactMap { $0.item?.id }) { old, new in
            currentItemID = ItemKeyboardNavigation.reconciled(currentItemID, old: old, new: new)
        }
        .onChange(of: keyboardItemID) { _, id in if let id { currentItemID = id } }
        .onKeyPress(keys: [.upArrow, .downArrow]) { press in
            guard !KeyboardInput.isEditingText, keyboardItemID != nil else { return .ignored }
            currentItemID = ItemKeyboardNavigation.next(from: currentItemID,
                in: rows.compactMap(\.item).filter { store.pendingCreationState(for: $0.id) == nil }.map(\.id),
                offset: press.key == .upArrow ? -1 : 1)
            keyboardItemID = currentItemID
            return .handled
        }
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Roadmap Options").font(.headline)
            Form {
                fieldPicker("Start Date", selection: Binding(get: { startFieldID }, set: { storedStartFieldID = $0 }))
                fieldPicker("Target Date", selection: Binding(get: { endFieldID }, set: { storedEndFieldID = $0 }))
                Toggle("Group by Status", isOn: $groupsByStatus)
                Slider(value: $titleWidth, in: 220...420) { Text("Title Column Width") }
            }
            Text("Choose the same iteration field for both dates to show its full duration. Items without dates remain visible as unscheduled.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                if let url = URL(string: project.url) { Link("Open in GitHub", destination: url) }
                Spacer()
                Button("Done") { showsOptions = false }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private func fieldPicker(_ title: LocalizedStringKey, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            Text("None").tag("")
            ForEach(dateFields) { field in Text(field.name).tag(field.id) }
        }
    }

    private func goToToday() {
        today = RoadmapCalendar.today
        todayRequest += 1
    }

    // One vertical scroller owns both columns. Only the timeline scrolls horizontally;
    // its measured offset also positions the fixed date header.
    private func timeline(_ rows: [Row], width: CGFloat) -> some View {
        let leftWidth = min(titleWidth, max(180, width * 0.45))
        let viewport = max(1, width - leftWidth - 1)
        let dayWidth = max(1, viewport / zoom.visibleDays)
        let dates = rows.flatMap { $0.schedule?.dates ?? [] } + [today]
        let earliest = dates.min()!
        let latest = dates.max()!
        // Keep the time axis fixed when a bar moves inside the current range.
        let first = min(timelineStart ?? RoadmapCalendar.adding(days: -31, to: earliest), earliest)
        let last = max(timelineEnd ?? RoadmapCalendar.adding(days: 366, to: latest), latest)
        let days = RoadmapCalendar.days(from: first, to: last) + 1
        let contentWidth = CGFloat(days) * dayWidth
        let height = rows.reduce(CGFloat.zero) { $0 + $1.height }
        let todayX = CGFloat(RoadmapCalendar.days(from: first, to: today)) * dayWidth
        let tickStep = zoom == .month ? 7 : (zoom == .quarter ? 14 : 60)
        let ticks = Array(stride(from: 0, to: days, by: tickStep))

        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("Title").font(.headline).padding(.horizontal, 12)
                    .frame(width: leftWidth, height: 36, alignment: .leading)
                Divider()
                Color.clear.overlay(alignment: .leading) {
                    ZStack(alignment: .topLeading) {
                        ForEach(ticks, id: \.self) { day in
                            Text(RoadmapCalendar.label(RoadmapCalendar.adding(days: day, to: first)))
                                .font(.caption).foregroundStyle(.secondary)
                                .offset(x: CGFloat(day) * dayWidth + 4, y: 10)
                        }
                    }
                    .frame(width: contentWidth, height: 36, alignment: .topLeading)
                    .offset(x: horizontalOffset)
                }
                .clipped()
                .accessibilityHidden(true)
            }
            .frame(height: 36)
            Divider()
            ScrollViewReader { verticalProxy in
                ScrollView(.vertical) {
                    HStack(alignment: .top, spacing: 0) {
                        LazyVStack(spacing: 0) {
                            ForEach(rows) { row in titleCell(row).frame(height: row.height).id(row.item?.id ?? "group:\(row.title)") }
                        }
                        .frame(width: leftWidth)
                        Divider()
                        ScrollViewReader { proxy in
                            ScrollView(.horizontal) {
                                VStack(spacing: 0) {
                                    ForEach(rows) { row in
                                        scheduleCell(row, first: first, dayWidth: dayWidth, width: contentWidth)
                                            .frame(height: row.height)
                                    }
                                }
                                .background {
                                    Canvas { context, size in
                                        var grid = Path()
                                        for day in ticks {
                                            let x = CGFloat(day) * dayWidth
                                            grid.move(to: CGPoint(x: x, y: 0))
                                            grid.addLine(to: CGPoint(x: x, y: size.height))
                                        }
                                        context.stroke(grid, with: .color(.secondary.opacity(0.15)), lineWidth: 1)
                                    }
                                }
                                .overlay(alignment: .topLeading) {
                                    Rectangle().fill(Color.accentColor.opacity(0.7))
                                        .frame(width: 1, height: height).offset(x: todayX)
                                        .allowsHitTesting(false).accessibilityHidden(true)
                                }
                                .overlay(alignment: .topLeading) {
                                    HStack(spacing: 0) {
                                        Color.clear.frame(width: todayX, height: 1)
                                        Color.clear.frame(width: 1, height: 1).id("today")
                                    }
                                    .allowsHitTesting(false).accessibilityHidden(true)
                                }
                                .background {
                                    GeometryReader { geometry in
                                        Color.clear.preference(key: RoadmapHorizontalOffset.self,
                                            value: geometry.frame(in: .named("roadmapHorizontal")).minX)
                                    }
                                }
                            }
                            .coordinateSpace(name: "roadmapHorizontal")
                            .onPreferenceChange(RoadmapHorizontalOffset.self) { horizontalOffset = $0 }
                            .onAppear { proxy.scrollTo("today", anchor: .center) }
                            .onChange(of: todayRequest) { _, _ in proxy.scrollTo("today", anchor: .center) }
                            .onChange(of: zoom) { _, _ in proxy.scrollTo("today", anchor: .center) }
                        }
                        .frame(height: height + 16)
                    }
                }
                .onChange(of: currentItemID) { _, id in
                    if let id { verticalProxy.scrollTo(id); if !KeyboardInput.isEditingText { keyboardItemID = id } }
                }
            }
        }
        .onAppear { timelineStart = first; timelineEnd = last }
        .onChange(of: first) { _, value in timelineStart = value }
        .onChange(of: last) { _, value in timelineEnd = value }
    }

    @ViewBuilder
    private func titleCell(_ row: Row) -> some View {
        if let item = row.item, let schedule = row.schedule {
            Button { activate(item) } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.title).lineLimit(1).foregroundStyle(.primary)
                    HStack(spacing: 6) {
                        Text(item.status ?? String(localized: "No Status"))
                        if store.isUpdatingRoadmap(itemID: item.id, projectID: project.id) {
                            Text("Syncing")
                        } else if let state = store.pendingSyncState(for: item) {
                            Text(syncTitle(state))
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focused($keyboardItemID, equals: item.id)
            .onKeyPress(.return) {
                guard !KeyboardInput.isEditingText, !isSelecting else { return .ignored }
                activate(item)
                return .handled
            }
            .onKeyPress(.space) {
                guard !KeyboardInput.isEditingText, isSelecting else { return .ignored }
                activate(item)
                return .handled
            }
            .disabled(store.pendingCreationState(for: item.id) != nil)
            .background(selectedItemIDs.contains(item.id) ? Color.accentColor.opacity(0.15) : Color.clear)
            .help("\(row.title)\n\(schedule.summary)")
            .accessibilityLabel("\(row.title), \(item.status ?? String(localized: "No Status")), \(schedule.summary)")
            .accessibilityAddTraits(selectedItemIDs.contains(item.id) ? .isSelected : [])
        } else {
            Text(row.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5))
        }
    }

    private func scheduleCell(_ row: Row, first: Date, dayWidth: CGFloat, width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            if let item = row.item, let schedule = row.schedule {
                if !schedule.dates.isEmpty {
                    RoadmapScheduleBar(
                        item: item, fields: project.fields, startFieldID: startFieldID, endFieldID: endFieldID,
                        first: first, dayWidth: dayWidth, color: statusColor(item),
                        isEditable: !isSelecting && store.canEditRoadmap(itemID: item.id, projectID: project.id),
                        isSaving: store.isUpdatingRoadmap(itemID: item.id, projectID: project.id),
                        focus: { currentItemID = item.id },
                        open: { activate(item) },
                        commit: { original, kind, days in
                            let startID = startFieldID
                            let endID = endFieldID
                            Task {
                                do {
                                    try await store.updateRoadmap(on: original, in: project.id,
                                        startFieldID: startID, endFieldID: endID, kind: kind, days: days)
                                } catch { reportError(error) }
                            }
                        }
                    )
                    .id("\(item.id).\(startFieldID).\(endFieldID).\(zoom.rawValue)")
                } else {
                    Text(schedule.summary).font(.caption).foregroundStyle(.secondary)
                        .padding(.leading, 12)
                        .offset(x: max(0, -horizontalOffset))
                }
            }
        }
        .frame(width: width, height: row.height, alignment: .leading)
        .background(row.item == nil ? Color.secondary.opacity(0.08) : Color.clear)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func statusColor(_ item: ProjectItem) -> Color {
        project.statusOptions.first { $0.id == item.statusOptionId }?.swiftUIColor ?? .secondary
    }

    private func activate(_ item: ProjectItem) {
        guard store.pendingCreationState(for: item.id) == nil else { return }
        if isSelecting {
            if selectedItemIDs.contains(item.id) { selectedItemIDs.remove(item.id) }
            else { selectedItemIDs.insert(item.id) }
        } else {
            showItemDetail(ItemInspectorReference(projectID: project.id, itemID: item.id))
        }
    }

    private func syncTitle(_ state: PendingSyncState) -> String {
        switch state {
        case .syncing: String(localized: "Syncing")
        case .failed: String(localized: "Failed")
        case .unconfirmed: String(localized: "Check GitHub")
        }
    }
}

/// Gesture drafts stay local; the Store owns every submitted update and its shared projection.
private struct RoadmapScheduleBar: View {
    let item: ProjectItem
    let fields: [ProjectField]
    let startFieldID: String
    let endFieldID: String
    let first: Date
    let dayWidth: CGFloat
    let color: Color
    let isEditable: Bool
    let isSaving: Bool
    let focus: () -> Void
    let open: () -> Void
    let commit: (ProjectItem, RoadmapEditKind, Int) -> Void

    private struct Drag {
        let id: UUID
        let item: ProjectItem
        let kind: RoadmapEditKind
        let dayWidth: CGFloat
        var days: Int
    }
    @GestureState private var gestureID: UUID?
    @State private var drag: Drag?
    @State private var cancelledGestureID: UUID?
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    private var activeDrag: Drag? { gestureID == drag?.id ? drag : nil }
    private var proposal: Result<RoadmapEdit, Error>? {
        guard let drag = activeDrag else { return nil }
        return Result {
            try RoadmapEdit.make(values: drag.item.fieldValues, fields: fields,
                startFieldID: startFieldID, endFieldID: endFieldID, kind: drag.kind, days: drag.days)
        }
    }
    private var schedule: RoadmapSchedule {
        if case .success(let edit) = proposal { return edit.schedule }
        return .make(values: item.fieldValues, fields: fields, startFieldID: startFieldID, endFieldID: endFieldID)
    }
    private var feedback: String? {
        switch proposal {
        case .success(let edit): edit.schedule.summary
        case .failure(let error): error.localizedDescription
        case nil: nil
        }
    }
    private var invalidProposal: Bool {
        if case .failure = proposal { return true }
        return false
    }

    var body: some View {
        let schedule = schedule
        let x = CGFloat(RoadmapCalendar.days(from: first, to: schedule.dates.first ?? first)) * dayWidth
        let span = schedule.start.flatMap { start in
            schedule.end.map { RoadmapCalendar.days(from: start, to: $0) + 1 }
        }
        let width = span.map { max(4, CGFloat($0) * dayWidth) } ?? 14
        let canResize = isEditable && span != nil && startFieldID != endFieldID
        ZStack(alignment: .leading) {
            Group {
                if span != nil {
                    RoundedRectangle(cornerRadius: 4).fill(color.opacity(isSaving ? 0.45 : 0.8))
                } else {
                    Image(systemName: schedule.start == nil ? "flag.fill" : "circle.fill")
                        .foregroundStyle(color)
                }
            }
            .frame(width: width, height: 22)
            .contentShape(Rectangle())
            .overlay {
                if isFocused || invalidProposal {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(invalidProposal ? Color.red : Color.accentColor, lineWidth: 2)
                }
            }
            .onTapGesture(perform: open)
            .gesture(gesture(.move), including: isEditable ? .all : .none)
            .focusable()
            .focused($isFocused)
            .onChange(of: isFocused) { _, focused in if focused { focus() } }
            .onKeyPress(.return) { open(); return .handled }
            .onKeyPress(.escape) {
                guard drag != nil else { return .ignored }
                cancelledGestureID = gestureID
                drag = nil
                return .handled
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(item.displayTitle), \(schedule.summary)")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, open)
            .accessibilityAction(named: Text("Edit Dates…"), open)
            .help(feedback ?? schedule.summary)
            .offset(x: x)

            if canResize && (isHovered || isFocused || activeDrag != nil) {
                handle(.start).offset(x: x - 10)
                handle(.end).offset(x: x + width)
            }
            if let feedback {
                Text(feedback).font(.caption2)
                    .foregroundStyle(invalidProposal ? Color.red : Color.primary)
                    .padding(.horizontal, 4).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 3))
                    .fixedSize().offset(x: max(0, x), y: -20)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Edit Dates…", action: open)
        }
    }

    private func handle(_ kind: RoadmapEditKind) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.primary.opacity(0.65)).frame(width: 8, height: 26)
            .contentShape(Rectangle())
            .gesture(gesture(kind))
            .help(kind == .start ? String(localized: "Drag to change start date") : String(localized: "Drag to change target date"))
            .accessibilityHidden(true)
    }

    private func gesture(_ kind: RoadmapEditKind) -> some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .global)
            .updating($gestureID) { _, id, _ in
                if id == nil { id = UUID() }
            }
            .onChanged { value in
                guard isEditable, let id = gestureID, id != cancelledGestureID else { return }
                if drag?.id != id {
                    isFocused = true
                    drag = Drag(id: id, item: item, kind: kind, dayWidth: dayWidth, days: 0)
                }
                guard let scale = drag?.dayWidth else { return }
                drag?.days = Int((value.translation.width / scale).rounded())
            }
            .onEnded { value in
                guard let draft = drag else { return }
                drag = nil
                guard isEditable else { return }
                let days = Int((value.translation.width / draft.dayWidth).rounded())
                guard let edit = try? RoadmapEdit.make(values: draft.item.fieldValues, fields: fields,
                    startFieldID: startFieldID, endFieldID: endFieldID, kind: draft.kind, days: days),
                    !edit.changes.isEmpty else { return }
                commit(draft.item, draft.kind, days)
            }
    }
}
