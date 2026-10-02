import SwiftUI

struct PersonalWorkView: View {
    @Bindable var store: ProjectStore
    #if os(iOS)
    @Binding var filter: MyWorkFilter
    #else
    let filter: MyWorkFilter
    #endif
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var search = ""
    @State private var status: PullRequestWorkStatus = .all
    @State private var searchPresented = false

    private var result: PersonalWorkResult? { store.personalWork[filter] }
    private var isLoading: Bool { store.loadingPersonalWork.contains(filter) }
    private var items: [PersonalWorkItem] {
        (result?.items ?? []).filter { item in
            (search.isEmpty || "\(item.title) \(item.repository) #\(item.number)".localizedCaseInsensitiveContains(search))
                && (filter == .assigned || status.includes(item.signals))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if filter != .assigned && status != .all {
                HStack {
                    Text(status.title).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear Filters") { status = .all }.font(.caption)
                }.padding(.horizontal).padding(.vertical, 8)
            }
            if let error = store.personalWorkErrors[filter] {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                Button("Retry", action: refresh).disabled(isLoading)
            }
            if let result, result.isTruncated {
                Text("GitHub search returned a limited set of results. Open GitHub to see more.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                if let url = searchURL {
                    Link("Open in GitHub", destination: url).padding(.bottom, 8)
                }
            }
            if isLoading && result == nil {
                ProgressView("Loading My Work…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.currentUserLogin == nil {
                ContentUnavailableView("Connect to GitHub", systemImage: "person.crop.circle",
                                       description: Text("Connect to GitHub in Settings to continue."))
            } else {
                List {
                    if items.isEmpty {
                        ContentUnavailableView("Nothing in \(filter.title)", systemImage: filter.icon,
                                               description: Text("No items match the current filters."))
                    }
                    ForEach(items) { item in
                        #if os(iOS)
                        NavigationLink {
                            MobileItemDetailView(store: store, personalItem: item)
                        } label: { itemRow(item) }
                        #else
                        itemRow(item)
                            .contextMenu { Link("Open in GitHub", destination: item.url) }
                        #endif
                    }
                }
                #if os(iOS)
                .listStyle(.plain)
                #endif
            }
        }
        #if os(iOS)
        .navigationTitle(filter == .authored ? String(localized: "My PRs") : filter.title)
        .navigationBarTitleDisplayMode(.inline)
        .mobileSearch(text: $search)
        #else
        .navigationTitle(filter.title)
        .searchable(text: $search, isPresented: $searchPresented, prompt: "Search title, repository, or #number")
        #endif
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Section("Scope") {
                        Picker("Scope", selection: $filter) {
                            Text("Assigned to Me").tag(MyWorkFilter.assigned)
                            Text("My PRs").tag(MyWorkFilter.authored)
                            Text("Review Requested").tag(MyWorkFilter.reviewRequested)
                        }
                        .pickerStyle(.inline)
                    }
                    if filter != .assigned {
                        Section("PR Status") {
                            Picker("PR Status", selection: $status) {
                                ForEach(PullRequestWorkStatus.allCases) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.inline)
                        }
                    }
                } label: {
                    Label("Filter", systemImage: filter != .assigned && status != .all
                          ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .accessibilityValue(filter.title)
            }
            #else
            if filter != .assigned {
                ToolbarItem(placement: .automatic) {
                    Menu {
                    Picker("PR Status", selection: $status) {
                        ForEach(PullRequestWorkStatus.allCases) { value in
                            Text(value.title).tag(value)
                        }
                    }

                    } label: {
                        Label("Filter", systemImage: status == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                    .accessibilityValue(status.title)
                }
            }
            #endif
            #if os(macOS)
            ToolbarItem(placement: .automatic) {
                if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Refresh My Work", systemImage: "arrow.clockwise") { refresh() }
                }
            }
            #endif
        }
        .task(id: "\(store.currentAccount?.id ?? ""):\(filter.rawValue)") {
            await store.refreshPersonalWork(filter)
        }
        .onChange(of: filter) { _, _ in search = ""; status = .all }
        .refreshable { await store.refreshPersonalWork(filter) }
        #if os(macOS)
        .focusedSceneValue(\.workspaceCommandContext, WorkspaceCommandContext(
            find: .init(id: "find", title: WorkspaceShortcut.find.title, shortcut: .find,
                        symbol: "magnifyingglass", perform: { searchPresented = true }),
            refresh: .init(id: "refresh-personal-work", title: String(localized: "Refresh My Work"),
                           isEnabled: !isLoading, shortcut: .refresh, symbol: "arrow.clockwise", perform: refresh)
        ))
        #endif
    }

    private func itemRow(_ item: PersonalWorkItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.isPullRequest ? "arrow.triangle.pull" : "smallcircle.filled.circle")
                .foregroundStyle(item.signals.isDraft ? Color.secondary : .green)
                .frame(width: 22, height: 24)
                .accessibilityLabel(item.isPullRequest ? "PR" : "Issue")
            VStack(alignment: .leading, spacing: 6) {
                Text(store.pendingContentEdits[item.id]?.title ?? item.title)
                    .font(.body).foregroundStyle(.primary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                Text("\(item.repository) #\(item.number)").font(.caption).foregroundStyle(.secondary)
                if item.isPullRequest { EngineeringSignalsView(signals: item.signals) }
            }
            #if os(iOS)
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
            #endif
            #if os(macOS)
            Spacer(minLength: 8)
            Link(destination: item.url) {
                Label("Open in GitHub", systemImage: "arrow.up.right.square").labelStyle(.iconOnly)
            }
            .accessibilityLabel("Open \(item.title) in GitHub")
            #endif
        }
        .padding(.vertical, 4)
    }

    private var searchURL: URL? {
        guard let login = store.currentUserLogin, let query = filter.searchQuery(login: login) else { return nil }
        var components = URLComponents(string: "https://github.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "type", value: "issues")]
        return components?.url
    }

    private func refresh() { Task { await store.refreshPersonalWork(filter) } }
}
