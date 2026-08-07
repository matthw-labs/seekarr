# Contributing to Seekarr

This project is under active development, so small focused contributions are preferred over large unsolicited refactors.

## Before You Start

If you want to work on a bug fix, a small improvement, or a documentation update, feel free to open a pull request.

If you want to introduce a larger feature, change architecture, or do a broad refactor, please open an issue first so the change can be discussed before you spend time implementing it.

## Reporting Issues

Before opening a new issue:

- Search existing issues first to avoid duplicates
- Use a clear and descriptive title
- Include reproduction steps for bugs
- Include screenshots or logs when useful
- Mention the platform involved (Android, iOS, macOS, etc.)

## Pull Request Guidelines

Please keep pull requests focused and easy to review.

### Good pull requests

- Solve one problem at a time
- Include a clear description of the change
- Explain why the change is needed
- Mention how the change was tested
- Update documentation when behavior or setup changes

### Avoid

- Unrelated refactors mixed into feature work
- Large drive-by formatting changes
- API keys, credentials, private URLs, signing files, or other secrets in commits

### Development Setup

Install dependencies:

```bash
flutter pub get
```

Run the app locally:

```bash
flutter run -d macos
```

### Per-worktree local files

The following files are gitignored and **must be present in every worktree / fresh checkout** before you can build or sign the app. They are intentionally kept out of version control because they contain local paths or signing credentials.

- `android/key.properties` — required for Android **release** builds. Copy from an existing worktree, or recreate from `android/key.properties.example` with real keystore values. Without it, `flutter run --release` on Android fails with a `Missing release signing config` error. Debug builds are unaffected.
- `macos/Runner/Configs/LocalSigning.xcconfig` — required for local macOS code signing.
- `ios/Flutter/LocalSigning.xcconfig` — required for local iOS code signing.

Other gitignored files that are typically per-developer rather than per-worktree: `.env`, `.env.local`, anything under `secrets/`, and `*.pem` / `*.key`. None of these break the standard build flow, but keep them out of commits.

### Required Checks
Before opening a pull request, run:

```bash
flutter analyze
dart format --output=none --set-exit-if-changed .
flutter test
```
Pull requests should **not** introduce analyzer issues, formatting drift, or failing tests.

### Project Structure

The project follows a feature-first layout:

- `lib/core/` for shared infrastructure and reusable widgets
- `lib/features/<feature>/data`
- `lib/features/<feature>/domain`
- `lib/features/<feature>/presentation`
Please keep new code aligned with the existing structure.

### Code Style

A few project conventions matter:

- Prefer small widgets and focused helpers
- Prefer readable, modular code over large build methods
- Keep stateful logic in Riverpod providers/notifiers where possible
- Use shared design tokens and reusable widgets instead of hardcoded UI values

### Tests

Tests should be deterministic and should not rely on real network calls.

When adding or changing logic, add or update tests where it makes sense.

### Documentation

If your change affects setup, configuration, behavior, or developer workflow, update the relevant documentation in the same pull request.

That includes **README.md** and any related docs.

### Security

Do not commit:

- API keys
- signing files
- local credentials
- private server URLs if they are sensitive
- `android/key.properties`
- `.env` files or similar local secrets
Use example files or placeholder values when documentation needs configuration examples.

### Licensing of contributions

Seekarr is licensed under the [Apache License 2.0](LICENSE). Unless you state
otherwise in writing, any contribution you intentionally submit for inclusion in
this project is offered under the same license — inbound equals outbound, as
described in section 5 of the license. No separate contributor agreement is
required.

Please sign off your commits to certify that you wrote the code, or otherwise
have the right to submit it under that license:

```bash
git commit -s -m "your message"
```

This adds a `Signed-off-by:` line, which is your agreement to the
[Developer Certificate of Origin](https://developercertificate.org/).

### Questions

If something is unclear, open an issue and ask before implementing a large change.
 