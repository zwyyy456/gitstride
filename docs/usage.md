# GitStride User Guide

[Back to README](../README.md)

### First Launch

New installations show a brief welcome window. Choose **Open GitHub Settings** to connect your account, or **Set Up Later** to continue without signing in. The welcome window does not appear again automatically; reopen it from **Help → Welcome to GitStride…** to review the introduction without resetting preferences or credentials. Existing account setups skip the automatic welcome.

Until you connect, the workspace and menu bar offer **Open GitHub Settings**. Pull request automation is an optional, separate connection in the same settings page.

### GitHub Connection

Open **Settings → GitHub → Account** to log in or disconnect. To change accounts or connection methods, disconnect first, then log in again. OAuth shows a device code: choose **Copy Code and Open GitHub**, paste it into Device activation, and approve access. You can close Settings while waiting; Cancel stops the login attempt.

The Release build can also use an existing GitHub CLI login. Switching connections clears the previous project cache and pending operations; complete or check any submitted work on GitHub before reconnecting. Background automation keeps its own connection.

### Menu Bar
Click the GitStride icon in your menu bar to see your projects. Select a project and browse issues by status.

### Search
Type in the search bar to filter issues by title or number. Use `@username` to filter by assignee.

### Quick Create
In the project window (Board or Table) or menu bar search field, type `>` followed by an issue title and press Return. GitStride opens the creation form with your input filled in. Confirm the repository and status, then choose **Create Issue**. Press Esc while typing to cancel quick-create input.

The new Issue form offers `Backlog` whenever the Project has a Status field. If you select it and the Project lacks that option, GitStride adds a gray `Backlog` option before creating the Issue. Other status options are left intact.

You can include Quick Entry qualifiers, for example `> Fix login repo:owner/repo status:Todo @me #bug`. Both `> Title` and `>Title` are accepted. Entering only `>` and pressing Return opens Quick Entry so you can finish the input there. Options that do not match the project stay in Quick Entry with a validation message.

### Project Layouts
Click "Open Board" or use the keyboard shortcut to open the project window. Switch between **Board**, **Table**, and **Roadmap** in the toolbar; GitStride remembers the layout for each project locally.

In Board, drag issues between status columns. Table uses aligned issue IDs, spacious rows, and collapsible status groups. Click a title to open details, or use native row selection and the item context menu. Click a column header to sort; when grouped, sorting applies within each status group.

Use **Display Options** to switch between status grouping and an ungrouped table, choose visible fields, or restore **Project Order**. On macOS 14.4 and later, multiple project fields can be shown as independent resizable, sortable columns. macOS 14.0–14.3 supports one selected project field column. Layout, grouping, column settings, and sorting are remembered per project locally.

In Roadmap, choose **Roadmap Options** to select start and target date or iteration fields. Selecting the same iteration for both endpoints shows its full duration. Use **Today** and **Month / Quarter / Year** to navigate the timeline. Options also control status grouping and title column width; these settings are copied when saving a work view. The title column stays visible during horizontal scrolling. Items without dates remain unscheduled; a single date shows a marker, and invalid ranges ask you to check the dates. Click a title or bar to edit fields in the existing detail view. Drag a schedule bar to move it, or drag its end handles to change the start or target date independently. Dates snap to whole days; iteration fields snap to existing iterations. A shared start/target field moves as a whole and has no independent resize handles. The preview shows the proposed dates; invalid ranges are not submitted. Press Escape to cancel a drag. Keyboard and VoiceOver users can open **Edit Dates…** from the bar to use the detail editor. Writes start only after release. If a multi-field update fails, confirmed changes are kept and GitStride refreshes the project; inspect the result before retrying. GitHub's public API does not expose roadmap date-field, zoom, or marker configuration, so saved roadmap configuration remains local.

Search and item filters carry across layouts. In Board, status filters change the cards without hiding columns; visible columns remain available even when no items match. Use **Display Options → Board Columns** to choose which status columns appear, or **Show All Columns** to reveal them without changing item filters. Hidden board status columns do not filter the table. Board and Table support the existing item context menu; all three layouts support bulk selection actions; layout preferences do not change saved views on GitHub.

### Work Views and Delivery

Use the toolbar’s Filter button for status, assignee, type, and label conditions; More Conditions contains milestone, parent issue, and completion. Display Options separately controls board column visibility, grouping, sorting, and visible fields. The ellipsis menu manages views saved on this Mac. Open in GitHub, My Work, and multiple selection remain direct toolbar actions. The content area has no permanent view/filter bar. Active conditions appear only while filtering and can be removed individually; **Clear Filters** clears item filters and search while preserving display preferences, including hidden board columns. The item count shows how many project items match the filters and search, including matches in hidden board columns. Board Columns reports how many status columns are shown.

Saved Views → Save Current View keeps the current filters, Board/Table/Roadmap layout, table sorting and columns, card fields, hidden board columns, and roadmap date fields, zoom, grouping, and title column width. Each saved view has independent display preferences. Filter edits are marked Modified until you choose Update Saved Filters; display preferences are remembered automatically. Search text is temporary. These preferences do not create or modify GitHub saved views.

For a defect view, choose the actual issue type or label your project uses, then save the view with a name such as Bugs. Filtering preserves the current layout and display preferences. Single-select fields use their configured option order when sorting.

Choose Delivery by Milestone or Delivery by Parent Issue to see completed and blocked counts, with All, Unfinished, and Blocked shortcuts. Counts cover only issues present in the current project, including hidden board columns, and ignore other active filters. A milestone remains repository-scoped; a parent can collect children from different repositories. Completion follows GitHub issue state, and blocked counts include only unfinished issues with unresolved dependencies.

Board cards emphasize a two-line title, repository and issue number, assignees, and selected project fields. Unresolved blockers remain visible. Display Options → Show Fields can add milestone, labels, engineering signals, and project fields using their GitHub names and identities. Both layouts keep Filter and Display Options together after the layout switcher.

Selecting an item in Board, Table, Roadmap, or My Work opens the detail page with Back navigation at every window width. You can also open the item in its own window.

Choose **Edit** in the detail toolbar (⌘E, or **Workspace → Edit Item…**) to change the title and Markdown description in place, then **Save** (⌘S) or **Cancel**. While editing, toggle **Preview** (⌘P) to switch between the Markdown source and rendered content. Press Return in the title to focus the description editor; while previewing, Return keeps the preview and title focus unchanged. Issue and PR edits update the original GitHub content in every project that references it; draft edits update the project draft. Editing becomes available after details load when you have permission to edit that content. Failed saves keep your input so you can retry.

### Pull Request Automation

Under **Automation service**, choose **Default service**, **Custom address**, or **Disabled**, then save and restart GitStride. A custom address must be an HTTPS origin without a path, query, fragment, or embedded credentials. The current service remains active until restart. Switching servers requires that server's own automation connection and does not stop processing on the previous server; pause or delete its connection first if needed.

Connect automation once from **Settings → GitHub → Pull Request Automation**. Every repository currently available to the GitHub App is included automatically, and closing Issues are updated in every matching personal Project. The selected Project supplies the Status mapping names used across Projects; In Progress and Done are required. For Ready pull requests, choose either `Move to In review` or `Keep in In progress`. The first choice reuses a case-insensitive `In review` match or adds an Orange `In review` only when a matching Project first needs it. The second never changes Project options. Automation never adds Backlog. The hosted Worker runs even when GitStride is closed, and a running app refreshes displayed Project data and Automation connection health when the Worker reports a change.

Automation waits 3 seconds before reading current PR states and updating linked Issue items. All linked closing PRs must be merged for Done; any open Draft keeps the Issue In Progress; otherwise an open Ready uses your review policy. We recommend disabling overlapping built-in Project Status workflows, but this is optional. The delay currently requires a Worker code change and deployment to adjust; it is not editable in GitStride.


The Worker temporarily processes GitHub Project Item responses to locate exact item identities. It does not persist or log private Issue content, and the desktop app stores its management token only in Keychain.

### Planning Model

GitStride keeps GitHub's native concepts separate:

- **Project** collects and presents work. Most projects can stay focused on one repository, while a project may still contain issues from several repositories.
- **Status** is the Project workflow state used by the board, such as Todo, In Progress, and Done. Avoid a second `Phase` field when it represents the same workflow.
- **Milestone** is a repository-scoped delivery target. GitStride loads milestones from the issue's repository and stores the selected milestone on the issue itself.
- **Parent/sub-issues and dependencies** express cross-repository delivery structure. Use a parent issue as the cross-repository delivery target, then attach sub-issues and blocking relationships from any repository.
- **Release** can remain an optional Project custom field when a lightweight grouping across repositories is useful. It is not synchronized with repository milestones.

Project field configuration remains managed on GitHub. If an existing `Phase` field duplicates `Status`, remove or repurpose it in the GitHub Project settings rather than maintaining two workflow fields.

### Item Inspector

The right-hand inspector groups project fields, issue properties (assignees, labels, milestone), and relationships in a native form. Unset dates display **Not Set**. Click a date to open its calendar, then choose **Done**, **Cancel**, or **Clear field**; browsing the calendar does not save changes. Text and number fields show their saved value until clicked: Return saves, Escape cancels, and clearing the input removes the value. Single-select and iteration fields save the selected option immediately.

Saving indicators and errors appear beside the affected property. Failed edits retain their draft for correction or retry. The detail toolbar keeps **Edit**, **More Actions**, and the inspector toggle; refresh, GitHub, new-window, and archive actions are available under **More Actions**.

### Command Palette

Use **⌘K** or **Workspace → Show Command Palette…** in the workspace or a detached item window. The menu bar popover also opens the palette in the workspace. Search commands, switch projects, open My Work views, or change the current layout. Use the compact scope menu to limit results to commands, projects, or loaded items. The keyboard help button opens **Keyboard Shortcuts**. The toolbar layout pop-up shows the current layout and offers Board, Table, and Roadmap.

The **Loaded Items** scope searches item titles, numbers (`#123`), and assignees (`@login`, `@me`) in the current account's project snapshots already held by GitStride. It includes followed projects and cached snapshots, independently of the current board filters. Cached results are marked. This is not a GitHub-wide search. Results show their repository and project; an issue in two projects has two entries because each membership has its own status.

Type to filter, then use Up/Down and Return to execute a result. For example, **⌘K → r → Return** refreshes the current view; typing `r` never executes by itself. Shortcut badges show alternatives outside the palette, not additional keys required inside it. Select **Change Status…** for the focused item, or for an item search result, to choose from its project's current status options. Read-only and syncing items cannot be changed. The palette also offers existing contextual actions; destructive commands require confirmation. Escape returns from a subpage or closes the palette. Closing restores the previous keyboard focus.

Keyboard navigation follows the visible order in tables, My Work, and roadmaps. On a board, Up/Down moves within a column and Left/Right moves to an adjacent nonempty visible column. Return opens details. In selection mode, Space toggles the current item's selection and Escape exits selection mode. Focus and bulk selection are separate; hovering does not choose a command target. Text editors and input-method composition retain their normal key handling.

The focused item supports **S** (status), **A** (assignees), **L** (labels), **P** (the project's single-select Priority field), **E** (edit title and description), and **⇧⌘C** (copy link). These actions also appear in the command palette and Workspace menu. Status and priority open searchable option lists; assignees and labels open searchable, checked lists directly. Labels are loaded from the current repository; assignee searches run as you type. Return applies a single option or toggles an assignee/label; Escape returns or closes. Commands opened inside the palette stay in the same panel. Unavailable actions explain their requirements in the palette. Priority field names are matched case-insensitively. Existing single-select options are preserved. If no Priority field exists, choosing Urgent, High, Medium, or Low creates it before assigning the value; opening, cancelling, or choosing Not Set does not create a field. Conflicting names/types and missing edit permission are reported. Retrying a failed assignment reuses a confirmed field. Labels currently apply to issues; assignees apply to issues and pull requests.

In tables, boards, roadmaps, and My Work, **X** toggles the focused item's selection, **Shift–Up/Down** extends or shrinks a range, and **⌘A** selects the visible items. Board ranges follow column order, then card order; hidden columns, collapsed table groups, and pending creations are excluded. **Escape** clears the selection and leaves selection mode. My Work supports batch status changes and archiving; cross-project status changes offer only names shared by every selected project, using each project's own option identity. A failed batch stops, reports the error, and keeps unfinished items selected.

In a project's content area, **C** opens item creation. Sidebar navigation uses Tab and arrow keys; typing a letter does not switch destinations. Opening a board card with the mouse does not bulk-select it. Returning preserves the browsing position, with a focus indicator for keyboard navigation rather than a persistent selection border for mouse browsing.

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘ K` | Show the command palette in the active workspace or item window |
| `⌘ F` | Search the current project view or My Work |
| `⌘ R` | Refresh the current context |
| `⇧ ⌘ R` | Refresh the project list |
| `⌘ N` | New project |
| `⇧ ⌘ N` | Add to project |
| `⌥ ⌘ I` | Toggle the item inspector |
| `⌘ ←` | Previous status tab in the menu bar popover, outside text input |
| `⌘ →` | Next status tab in the menu bar popover, outside text input |
| `> title` + `Return` | Open a prefilled creation form from project or menu bar search |
| `Esc` | Cancel quick-create input in search |

### Default scheduling fields

Issue creation always offers optional **Start date** and **Target date** inputs. Existing date fields with these names are reused (case-insensitive). A missing field is created only after submitting a value for it; leaving both dates empty does not create fields. Conflicting field types or duplicate names report an error. Field preparation happens before Issue creation, and retries query GitHub before creating missing fields. Confirmed Issues and field writes are retained when resuming a failed submission.

Roadmap defaults to these two date fields until you save a field selection, including when the fields first become available. An explicit None selection stays empty. Saved custom mappings remain selected while their fields are available; a removed or incompatible field displays as None until you choose another field. Date values are shared with GitHub; the roadmap mapping is local to GitStride.

**Ready to Merge** requires a non-draft PR without conflicts, GitHub's `CLEAN` merge status, no required or rejected review, and no failed, pending, or expected checks. Approval is not mandatory for repositories without required reviews. This reports the last fetched state; GitHub still determines permissions and final merge availability when you open the PR.
