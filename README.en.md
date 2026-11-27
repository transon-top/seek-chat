<p align="center">
  <img src="docs/images/logo.png" alt="SeekChat" width="120">
</p>

# SeekChat

English | [简体中文](README.md)

A Flutter chat client for DeepSeek, currently shipping on **Android**.

> This is a personal app shared publicly: it evolves around one person's usage,
> comes with no commercial support, and is not guaranteed to work on every
> device.

The model is fixed to `deepseek-flash`. The API origin defaults to
`https://api.deepseek.com` and can be overridden with
`--dart-define=SEEK_CHAT_API_ORIGIN=<origin>`.

## Privacy

- **No telemetry, no ads**: no analytics, tracking, ad, crash-reporting, or push
  SDKs, and no usage data sent to third-party servers.
- **Your key only**: no API key is bundled. Enter your own DeepSeek API key in
  Settings after launch.
- **DeepSeek official API only**: chats, attachment uploads, speech
  transcription, and read-aloud all go to one API origin — the official
  `https://api.deepseek.com` by default. The key appears only in that origin's
  `Authorization` header and is never written to the database, logs, or export
  archives.
- **Exceptions**: site icons for web-search sources are loaded from the URLs in
  search results; links you tap open in your system browser and are not fetched
  by the app.
- **Markdown images are never loaded**, only shown as clickable URLs.
- Sessions, attachments, and settings stay on the device. The API key lives in
  `flutter_secure_storage`, and Android backup is disabled
  (`allowBackup=false`).

## Features

- Streaming replies, stop, regenerate, edit question, continue, and branch switching
- Markdown, syntax highlighting and copy, math, Mermaid diagrams, links, and images
- Web search and deep thinking toggles, tool timeline, and citations
- File attachments, image strip, hold-to-talk transcription, and read-aloud
- Session grouping, search, pinning, multi-select, rename, and delete
- History import/export, light/dark theme, font size, language, and location settings
- Input/output moderation, error classification, and localized copy

Full behavior specs live in [docs/features/](docs/features/README.md).

## Requirements

- Flutter 3.50.0 (stable, matching the release pipeline)
- Dart SDK `^3.14.0`
- JDK 21 and the Android SDK (needed to build Android)

## Getting started

```bash
flutter pub get
flutter run
```

After launch, enter your DeepSeek API key in **Settings → API Key**. The key is
stored only in `flutter_secure_storage` — never in the database, logs, or
export archives.

## Building an APK

```bash
./tool/build_android_apk.sh
```

Builds per-ABI APKs and renames them to `SeekChat-<abi>-release.apk` under
`build/app/outputs/flutter-apk/`. A release build requires
`android/key.properties` and a real keystore; it fails immediately without them.

## Development

```bash
dart run build_runner build --delete-conflicting-outputs   # after drift schema changes
flutter gen-l10n                                           # after ARB changes
flutter analyze
flutter test
./tool/ci/local_checks.sh                                  # generated-file drift + analyze + test
```

Generated files (`database.g.dart`, `lib/l10n/generated/`) are committed and
must be regenerated after changes.

Git hooks: `brew install lefthook`, then run `./tool/ci/install_git_hooks.sh`
once per machine (pre-push runs `local_checks.sh`).

## Releasing

Push a `v*` tag on `main` to trigger
[.github/workflows/release.yml](.github/workflows/release.yml), which validates
the version, builds and signs the APK, and creates a draft Release. See
[docs/runbooks/release.md](docs/runbooks/release.md).

## Project layout

```text
lib/
  app/        startup, routing, theme, and localization
  features/   chat, sessions, history, settings
  shared/     API, data layer, models, widgets, secure storage
  l10n/       ARB files and generated output
docs/
  features/   behavior specs for implemented features (authoritative)
  adr/        architecture decisions
  runbooks/   release runbook
```

Dependency direction is `app → features → shared`; `shared/` never imports
`features/`.

## Documentation

- Feature specs: [docs/features/](docs/features/README.md)
- Glossary: [GLOSSARY.md](GLOSSARY.md)
- Architecture decisions: [docs/adr/](docs/adr/)
