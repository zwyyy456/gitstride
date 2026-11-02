# GitStride Repository Guidelines

## Project Facts

- GitStride is a native SwiftUI menu bar app for macOS 14+, built from `GitStride.xcodeproj` with the `GitStride` scheme.
- Both distributions use OAuth Device Flow and URLSession for GitHub access. The GitHub Release target also supports existing `gh` credentials and Sparkle updates.
- The repository contains `GitStride` (GitHub Release), `GitStrideAppStore` (OAuth-only multiplatform target: native macOS 14+ and iOS/iPadOS 17+), and the focused `GitStrideTests` unit test target.
- `docs-index.md` is the command and document index; it does not define engineering rules.

## Document Routing

| Change | Read |
| --- | --- |
| App composition, scene lifetime, state ownership, concurrency, persistence, GitHub integration, or directory boundaries | `architecture.md` |
| Code location or an unfamiliar execution path | `docs/overview.md` |
| Build and behavior validation | `docs/testing/validation-reference.md` and the command entry in `docs-index.md` |

## Project Constraints

- Long-lived engineering rules belong in `architecture.md`. Keep product descriptions and usage instructions in `README.md`; do not turn them into engineering requirements.

## Validation

- The default compile check is the macOS app build documented in `docs-index.md`.
- Do not launch or relaunch the app, or capture screenshots, as post-build visual validation. When visual evidence is needed, rely on screenshots provided by the user from their running app.
