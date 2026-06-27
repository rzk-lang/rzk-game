# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/), and the project follows the [Haskell Package Versioning Policy](https://pvp.haskell.org/) (PVP). Under the PVP the first two version components form the major version, bumped on a breaking change to the exported API. The third component is bumped on a compatible addition, and the fourth on a change with no API effect.

## [Unreleased]

## [0.3.0] - 2026-06-27

### Added

- Sections can be grouped into chapters, shown as headings in the level picker; an untitled chapter renders its sections at the top level ([#39](https://github.com/rzk-lang/rzk-game/pull/39)).
- Structured inventory entries: a granted lemma carries a name, a synopsis, and an optional type (otherwise derived from the prelude) ([#40](https://github.com/rzk-lang/rzk-game/pull/40)).
- A `forbidden:` list bans always-available eliminators (`idJ`, `first`, `second`, `recOR`) per level — dropped from the moves, and failing a gated check if used ([#41](https://github.com/rzk-lang/rzk-game/pull/41)).
- Granted lemmas surface as tap-to-fill hole moves ([#35](https://github.com/rzk-lang/rzk-game/pull/35)).
- A "How holes work" page, with a persistent "❓ Holes" link in the header ([#37](https://github.com/rzk-lang/rzk-game/pull/37)).
- URL-hash page addresses: a refresh stays put, levels deep-link, and back/forward navigate ([#31](https://github.com/rzk-lang/rzk-game/pull/31)).
- Marking a pre-test "I already know this" advances to the next incomplete page ([#29](https://github.com/rzk-lang/rzk-game/pull/29)).
- Clearer progress: the header shows "Chapter › Section" with an overall bar, the breadcrumb the current section, the footer the position ("Page X of N"); the map shows per-chapter progress and counts starred extras separately ([#43](https://github.com/rzk-lang/rzk-game/pull/43)).

### Changed

- **Breaking (game spec).** Authored as `chapters:` instead of a flat `sections:`, and structured inventory entries replace `name : type` strings; a downstream `game.yaml` needs migration ([#39](https://github.com/rzk-lang/rzk-game/pull/39), [#40](https://github.com/rzk-lang/rzk-game/pull/40)).
- The win-check carries the goal's `uses (…)`, so a level may require a named assumption such as `funext` ([#36](https://github.com/rzk-lang/rzk-game/pull/36)).
- Progress and drafts are keyed by puzzle id (with a one-time migration), so reordering levels no longer corrupts saved progress ([#32](https://github.com/rzk-lang/rzk-game/pull/32)).
- The inventory advisory is split into a hard gate (`gated: true`) and an informational soft notice, and ignores lemmas the reference solution itself uses ([#33](https://github.com/rzk-lang/rzk-game/pull/33)).
- Declared types are recovered with rzk's parser instead of a text scanner ([#42](https://github.com/rzk-lang/rzk-game/pull/42)).
- The rzk typechecker is pinned to v0.9.1 ([#35](https://github.com/rzk-lang/rzk-game/pull/35), [#41](https://github.com/rzk-lang/rzk-game/pull/41)).

### Fixed

- A typechecker crash is caught as a recoverable result instead of freezing the app, and a result that no longer matches the edited proof is flagged stale ([#38](https://github.com/rzk-lang/rzk-game/pull/38)).
- Via the rzk v0.9.1 pin: a multi-variable binder hole no longer crashes (rzk[#263](https://github.com/rzk-lang/rzk/pull/263)), a shape-restricted argument hole is reported with its goal (rzk[#267](https://github.com/rzk-lang/rzk/pull/267)), long-spine lemma candidates are kept (rzk[#261](https://github.com/rzk-lang/rzk/pull/261)), and an unused `uses` is tolerated in lenient mode (rzk[#262](https://github.com/rzk-lang/rzk/pull/262)).

### Internal

- The `unsafePerformIO` globals are replaced by an explicit `GameEnv` ([#34](https://github.com/rzk-lang/rzk-game/pull/34)); FFI goes through `Miso.FFI.QQ` ([#28](https://github.com/rzk-lang/rzk-game/pull/28)).

## [0.2.0] - 2026-06-19

### Added

- Goal/context-matched hints. A level carries an ordered `hints` list, hidden until the player asks. Plain hints reveal one at a time; a contextual hint with a `when-goal` trigger surfaces only while it matches the focused hole's goal.
- Inventory gating. A level restricts the player to the lemmas it grants. A violation is a soft notice by default, or fails the check when the level sets `gated: true`. The granted lemmas are shown in an "Allowed here" list beside the moves.
- An author-facing authoring guide, `docs/authoring.md`.

### Changed

- The type error now leads with its message rather than the global context dump.
- The controls (Check, Format, Undo, Reset) move into a sticky action bar, separate from the per-hole moves.

## [0.1.0] - 2026-06-18

### Added

- First release. The playable engine (miso compiled to WebAssembly, with rzk's typechecker running in the browser) and the built-in game.
- Reusable release artifacts consumed by `rzk-game-action` and downstream game repositories: the wasm engine tarball and the portable native bundler.
- Content from data. A `game.yaml` table of contents plus one file per item, with a native bundler producing `public/game.json`.
- Progress export, import, and reset.
- A Format action with an opt-in format-on-check.

[Unreleased]: https://github.com/rzk-lang/rzk-game/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/rzk-lang/rzk-game/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/rzk-lang/rzk-game/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/rzk-lang/rzk-game/releases/tag/v0.1.0
