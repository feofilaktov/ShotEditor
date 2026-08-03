# Contributing to ShotEditor

Thanks for your interest in improving ShotEditor! This is a small, focused
macOS app — contributions of all sizes are welcome.

## Getting started

```sh
git clone https://github.com/<you>/shoteditor.git
cd shoteditor
make build      # or: swift build
make run        # build + launch
make test       # unit tests + visual smoke test
```

Requirements: macOS 13+, Xcode command-line tools (Swift 5.9+).

## Project layout

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for a module-by-module map.

## Development workflow

1. Create a branch off `main`.
2. Make your change. Keep it focused; match the surrounding code style
   (no linter is enforced, but follow existing naming and formatting).
3. Add or update tests in `Tests/ShotEditorTests/` — `make test` must pass.
4. Update `CHANGELOG.md` under an `## [Unreleased]` heading.
5. Open a pull request describing the change and, for UI work, include a
   before/after screenshot.

## Guidelines

- **Keep it local-first.** ShotEditor intentionally has no cloud, accounts, or
  telemetry. Network features (if any) must be strictly opt-in and off by default.
- **No new heavy dependencies** without discussion — the app ships as a single
  small universal binary.
- **Cover logic with tests.** Rendering/geometry/export changes should come with
  a test (the suite already guards against e.g. retina pixel-doubling).

## Reporting bugs / requesting features

Use the issue templates. Please include your macOS version and steps to
reproduce.

## License

By contributing, you agree that your contributions are licensed under the
project's [MIT License](LICENSE).
