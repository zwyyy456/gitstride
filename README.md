# GitStride · 迹程

English · [简体中文](README.zh-CN.md)

A native macOS app for GitHub Projects. Check projects from the menu bar, organize work in Board or Table, and edit issues without switching to the browser.

[Website](https://gitstride.hyperseek.tech) · [Download](https://gitstride.hyperseek.tech/download) · [Documentation](https://gitstride.hyperseek.tech/docs) · [GitHub Releases](https://github.com/zwyyy456/GitStride/releases)

## Features

- **Menu bar and workspace** — check projects quickly, or open a full window with Board, Table, Roadmap, search, and filters.
- **My Work and local views** — find work across projects and save filters and display preferences on your Mac.
- **Issue editing** — create issues and manage assignees, labels, milestones, parent/sub-issues, and dependencies.
- **Project notifications** — get configured reminders about status, assignment, and due dates while the app runs.
- **Optional PR automation** — update matching personal Projects as linked pull requests progress, even after you quit the app.

Available in English and Simplified Chinese. GitHub project names, custom statuses, and user content keep their original text.

## Quick start

Requires **macOS 14 (Sonoma) or later** and a GitHub.com account. Desktop browsing supports personal and organization Projects; GitHub Enterprise Server is not supported.

1. [Download GitStride](https://gitstride.hyperseek.tech/download), extract the ZIP, and move the app into Applications.
2. Open the app, sign in under **Settings → GitHub → Account**, and follow the GitHub device authorization prompts.
3. Choose your personal account or organization and open an existing Project.

The GitHub Release build can also reuse a `gh` login; see the [getting started guide](https://gitstride.hyperseek.tech/docs/getting-started). PR automation uses separate, optional authorization and is not required to browse or edit projects.

Desktop OAuth requests `repo project read:org offline_access`; `repo` includes private repository access and code read/write permissions. OAuth credentials stay in macOS Keychain; the local project cache can contain unencrypted private content. See [privacy and permissions](https://gitstride.hyperseek.tech/privacy) for details.

## Documentation and support

- [Workspace and views](https://gitstride.hyperseek.tech/docs/workspace) — Board, Table, search, quick create, and My Work.
- [PR automation](https://gitstride.hyperseek.tech/docs/automation) — authorization, status rules, and pausing or deleting a connection.
- [Self-hosting](https://gitstride.hyperseek.tech/docs/self-hosting) — connect your own automation service; deployment steps are in the [Worker guide](Automation/README.md).
- [Troubleshooting](https://gitstride.hyperseek.tech/support) · [In-repository user guide](docs/usage.md) for Roadmap, command palette, and detailed workflows.

Report problems in [GitHub Issues](https://github.com/zwyyy456/GitStride/issues) with the app version, macOS version, and reproduction steps. Remove tokens and private content from diagnostics and screenshots.

## Building from source

The current development toolchain is Xcode 26.5. macOS 14 is the app's deployment target, not the required version of Xcode.

```bash
git clone https://github.com/zwyyy456/GitStride.git gitstride
cd gitstride
xcodebuild -project GitStride.xcodeproj -scheme GitStride \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

For running from Xcode, open `GitStride.xcodeproj`, select the GitStride target, and choose your own development team under Signing & Capabilities. Sparkle uses hardened-runtime library validation, so an unsigned compile check does not establish that the app can launch locally.

The `GITSTRIDE_OAUTH_CLIENT_ID` build setting is a public desktop OAuth App ID. For your own distribution, register an OAuth App, enable Device Flow, and set its Client ID on both app targets. Do not embed a Client Secret. The `GitStrideAppStore` scheme supports OAuth login only and excludes Sparkle; this build target does not imply availability in the Mac App Store.

The `GitStrideAppStore` target and scheme support native macOS and iPhone/iPad (iOS 17+); select the corresponding run destination in Xcode. See the [iOS guide](docs/ios.md) for its current scope and build instructions. This does not imply App Store availability.

See [validation commands](docs-index.md#5-常用验证命令), [architecture](architecture.md), and the [release guide](docs/releasing.md). Worker development separately requires Node.js 22 or later; instructions are in [Automation/README.md](Automation/README.md).

## Origin and license

GitStride originated from [yogesharc/GitBoard](https://github.com/yogesharc/GitBoard) and is now independently maintained and substantially reworked by [zwyyy456](https://github.com/zwyyy456). The original copyright notice is preserved alongside the current maintainer's notice.

Released under the [MIT License](LICENSE). The license is also included in the app bundle. GitStride is not affiliated with GitHub, Inc.
