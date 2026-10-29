# CommandBacktick

Native macOS AppKit menu-bar app built with Swift Package Manager. No dependencies.
Run checks sequentially with `nice -n 10 swift test --jobs 1` and package with
`nice -n 10 ./scripts/build-app.sh`. Keep README limitations accurate.
Never include local profile metadata, pictures, real window titles, or diagnostics
containing them in repository files. Test fixtures must be synthetic.
Do not enable another app's conflicting shortcut during tests. Do not publish
without a user request.

This repository uses main only, with no pull requests. Do not create tags,
GitHub releases, or release automation. Keep diagnostics behind --debug and
document source installation, permission changes, and platform limitations.
