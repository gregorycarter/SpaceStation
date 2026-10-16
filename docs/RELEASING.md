# Releasing SpaceStation

`scripts/release.sh` builds the app and packages it as a `.dmg` in `dist/`.

## Two routes

| | Signed and notarized (recommended) | Unsigned (free) |
|---|---|---|
| Command | `scripts/release.sh` | `scripts/release.sh --unsigned` |
| Cost | Apple Developer Program, USD 99 / year | Free |
| First launch for users | Opens normally | Blocked; users must click **Open Anyway** in System Settings > Privacy & Security (macOS 15 removed the Control-click shortcut) |
| Accessibility permission | Survives updates (stable signature) | Must be re-allowed after every update |
| Homebrew cask | Possible | Homebrew has been dropping casks that fail Gatekeeper; use your own tap |

## One-time setup for the signed route

1. **Join the Apple Developer Program** at <https://developer.apple.com/programs/> (Apple ID with
   two-factor authentication; individual enrolment is fine). Notarization has no extra fee.
2. **Create a Developer ID Application certificate.** In Xcode: Settings > Accounts > select your team
   > Manage Certificates > **+** > *Developer ID Application*. Find its exact name with:
   ```bash
   security find-identity -v -p codesigning
   ```
   It looks like `Developer ID Application: Your Name (ABCDE12345)`.
3. **Create an app-specific password** at <https://account.apple.com> > Sign-In and Security >
   App-Specific Passwords, then store notarization credentials in your keychain once:
   ```bash
   xcrun notarytool store-credentials "SpaceStation-notary" \
     --apple-id you@example.com --team-id ABCDE12345
   ```
   (It prompts for the app-specific password. Nothing secret is written to the repository.)

## Cutting a release

1. Set the version in `project.yml` (`MARKETING_VERSION`, and increase `CURRENT_PROJECT_VERSION`),
   run `xcodegen generate`, and commit both.
2. Make sure `main` is what you want to ship (tests pass: see CONTRIBUTING.md).
3. Run:
   ```bash
   export DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (ABCDE12345)"
   export NOTARY_PROFILE="SpaceStation-notary"
   scripts/release.sh
   ```
   The script checks the working tree is clean and the Xcode project is up to date, builds a Release
   with Hardened Runtime and a secure timestamp, verifies the signature, submits the app to Apple's
   notary service (usually a few minutes), staples the ticket, builds the `.dmg`, signs, notarizes and
   staples that too, runs the same Gatekeeper check a user's Mac will, and writes a SHA-256 checksum.
   If Apple rejects the submission the script prints Apple's log explaining why.
4. **Test it like a user:** download the `.dmg` in a browser on another Mac (so it is quarantined),
   drag the app to Applications and open it. There should be no warning.
5. Tag and publish:
   ```bash
   git tag v1.0.0 && git push origin v1.0.0
   gh release create v1.0.0 dist/SpaceStation-1.0.0.dmg dist/SpaceStation-1.0.0.dmg.sha256 \
     --title "SpaceStation 1.0.0" --notes "..."
   ```

## The unsigned route

`scripts/release.sh --unsigned` produces `SpaceStation-<version>-unsigned.dmg`. Say plainly in the
release notes that it is unsigned, how to open it (Open Anyway), and that Accessibility has to be
re-allowed after each update.

## Updates

SpaceStation does not update itself. Users download the new `.dmg` from the Releases page and replace
the app. A signed build keeps the Accessibility permission across that replacement; an unsigned one
does not.
