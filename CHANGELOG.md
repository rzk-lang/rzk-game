# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/), and the project follows the
[Haskell Package Versioning Policy](https://pvp.haskell.org/) (PVP). Under the
PVP the first two version components form the major version, bumped on a
breaking change to the exported API. The third component is bumped on a
compatible addition, and the fourth on a change with no API effect.

## [Unreleased]

## [0.2.0] - 2026-06-19

### Added

- Goal/context-matched hints. A level carries an ordered `hints` list, hidden
  until the player asks. Plain hints reveal one at a time; a contextual hint with
  a `when-goal` trigger surfaces only while it matches the focused hole's goal.
- Inventory gating. A level restricts the player to the lemmas it grants. A
  violation is a soft notice by default, or fails the check when the level sets
  `gated: true`. The granted lemmas are shown in an "Allowed here" list beside
  the moves.
- An author-facing authoring guide, `docs/authoring.md`.

### Changed

- The type error now leads with its message rather than the global context dump.
- The controls (Check, Format, Undo, Reset) move into a sticky action bar,
  separate from the per-hole moves.

## [0.1.0] - 2026-06-18

### Added

- First release. The playable engine (miso compiled to WebAssembly, with rzk's
  typechecker running in the browser) and the built-in game.
- Reusable release artifacts consumed by `rzk-game-action` and downstream game
  repositories: the wasm engine tarball and the portable native bundler.
- Content from data. A `game.yaml` table of contents plus one file per item,
  with a native bundler producing `public/game.json`.
- Progress export, import, and reset.
- A Format action with an opt-in format-on-check.

[Unreleased]: https://github.com/rzk-lang/rzk-game/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/rzk-lang/rzk-game/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/rzk-lang/rzk-game/releases/tag/v0.1.0
