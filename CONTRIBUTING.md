# Contributing to Beacon

Thanks for helping improve Beacon. Contributions are welcome via **GitHub pull requests**. The maintainer reviews and merges changes that fit the project.

## Ground rules

1. **MIT License** — by opening a PR you license your work under the same MIT terms as Beacon (see [LICENSE.md](LICENSE.md)).
2. **No secrets** — never commit API keys, Keychain dumps, `.env` files, or personal paths with credentials.
3. **macOS first** — target the current project deployment (see `MACOSX_DEPLOYMENT_TARGET` in the Xcode project).
4. **Keep the island stable** — avoid resizing the floating `NSPanel` on expand/collapse (that caused Auto Layout crashes). Prefer fixed panel size + SwiftUI `progress` animation.
5. **Agent tools** — anything that runs shell, files, or AppleScript must keep **user permission** dialogs for sensitive actions.

## How to contribute (PRs)

```text
1. Fork the repository on GitHub
2. Clone your fork
3. Create a branch:  git checkout -b feature/short-name
4. Build & test locally (see below)
5. Commit with a clear message
6. Push to your fork
7. Open a Pull Request against main
```

### Local build

```bash
git clone https://github.com/<your-user>/Beacon.git
cd Beacon
xcodebuild -project Beacon.xcodeproj -scheme Beacon -configuration Debug -derivedDataPath DerivedData build
open DerivedData/Build/Products/Debug/Beacon.app
```

Or open `Beacon.xcodeproj` in Xcode and Run.

### Before you open a PR

- [ ] Builds cleanly in Xcode / `xcodebuild`
- [ ] No API keys or personal data in the diff
- [ ] Short description of **what** and **why**
- [ ] Screenshots or a short screen recording if you change UI
- [ ] Update README if you add user-facing features

## Ideas that help

- New AI providers / model presets
- Better agent tools with safer permissions
- Accessibility and localization
- Tests for URL builders / tool JSON parsing
- Packaging / notarization docs

## Issues

Use GitHub Issues for bugs and feature requests. Include:

- macOS version and Beacon build
- Steps to reproduce
- Expected vs actual behaviour
- Relevant logs (redact keys)

## Code of conduct

Be respectful. Harassment or bad-faith contributions will be rejected and may lead to blocked PRs.
