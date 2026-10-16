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

## Signing and the Accessibility permission

SpaceStation needs the macOS Accessibility permission to switch Spaces. macOS ties that
permission to the app's code signature. With no signing certificate Xcode signs **ad-hoc**,
which identifies the app only by a hash of that exact build, so **every rebuild looks like a
different app**: System Settings still shows SpaceStation as enabled, but the permission no
longer applies and the app reports it as not granted.

To avoid this, sign your local builds with a stable certificate (a free Apple ID "Personal
Team" is enough):

1. Xcode → Settings → Accounts → add your Apple ID.
2. `cp Config/Local.xcconfig.example Config/Local.xcconfig` and set `DEVELOPMENT_TEAM` to your
   Team ID. `Local.xcconfig` is git-ignored.
3. Rebuild, then grant Accessibility once. It will now survive rebuilds.

If you must run an ad-hoc build, use **Reset & try again** in the setup window after each
rebuild (it runs `tccutil reset Accessibility com.gregorycarter.SpaceStation`). Also avoid
keeping several copies of the app with the same bundle ID (e.g. one in `/Applications` and one
in DerivedData); they share a single permission entry and the login item may launch the wrong one.

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
