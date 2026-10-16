# Contributing

Thanks for your interest in SpaceStation! Bug reports, fixes and small
features are welcome.

## Setup

Requirements: macOS 13+, Xcode 15+, and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`).

`project.yml` is the source of truth for the Xcode project. After changing it
(adding files, targets or build settings), run:

```bash
xcodegen generate
```

and commit the regenerated `SpaceStation.xcodeproj` along with `project.yml`.
CI fails if the two are out of sync.

## Build and test

```bash
xcodebuild test -project SpaceStation.xcodeproj -scheme SpaceStation \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Unit tests live in `Tests/SpaceStationTests`. The parsing of the private
Space data and of the system shortcut preferences is deliberately written as
pure functions so it can be tested without a live WindowServer.

## Guidelines

- Keep it dependency-free: Apple system frameworks only.
- Don't add network access, telemetry or file access. See [SECURITY.md](SECURITY.md).
- Any new use of a private API or a new permission/entitlement needs a
  justification in the pull request and an update to `SECURITY.md`.
- Keep commits focused; add or update tests for logic changes.
- By contributing you agree your work is released under the [MIT License](LICENSE).

## Reporting security issues

Please don't open a public issue; see [SECURITY.md](SECURITY.md).
