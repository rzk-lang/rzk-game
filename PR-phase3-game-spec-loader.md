# Phase 3: game spec format and loader

Create the PR: https://github.com/fizruk/rzk-game/pull/new/phase3-game-spec-loader

---

Phase 3: lift game content out of Haskell into an authorable spec + loader, reaching the Phase 3 exit (load a section from data and play it).

A game is a table of contents (`game.yaml`) plus one self-contained file per item. Each level file carries its intrinsic metadata in a YAML front-matter header and its prose in the Markdown body (intro before the first rzk block, conclusion under a trailing `## Conclusion`); the table of contents keeps only placement metadata — curriculum role, prerequisites, remedies — so a level file is portable and the locking graph stays in one place. For example, `game.yaml` lists `- puzzle: { file: levels/my-id.rzk.md }` and that file is:

````markdown
---
id: my-id
title: "The identity morphism"
statement: "hom A x x"
inventory:
  - "x        : A"
---

A morphism $x \to y$ is a path along $\Delta^1$. The identity is the constant path. Build it.

```rzk prelude
#def hom (A : U) (x y : A) : U := …
```

```rzk template
#def my-id (A : U) (x : A) : hom A x x := ?
```

```rzk solution
#def my-id (A : U) (x : A) : hom A x x := \ t → x
```

## Conclusion

The constant path is the identity morphism.
````

The pipeline turns this into the `[Section]` the engine already consumes:

- `RzkGame.Spec` — the FromJSON schema, the `.rzk.md` block splitter, the body readers (`levelProse`), and `goalFromTemplate` (recovers the pinned goal's closed Pi-type).
- `RzkGame.Loader.buildGame :: ByteString -> Either Text [Section]` — decodes a `game.json` bundle and assembles the sections; pure and total, so it falls back cleanly.
- `rzk-game-bundle` (native) — parses `game.yaml` and each file's front-matter, splits front-matter from body, and packs everything into one `public/game.json` (so the wasm app parses only JSON).
- `index.js` fetches the bundle before `hs_start`; `Main.loadGame` builds the sections, falling back to the built-in `RzkGame.Content`.
- All four worlds (15 levels, 9 prose pages) are ported to `game/` and reproduce the built-in sections exactly; `RzkGame.Content` stays as the fallback and the fixture the loader is checked against.

Templates keep the gentle grouped-binder style instead of the closed-form D2 suggested; `goalFromTemplate` reconstructs the closed Pi-type either way, so the ported world plays identically. Native builds use `cabal.project.native`, since the miso pin cannot resolve under a stock native GHC.

Verified: native `make test` (round-trips Content Morphisms exactly, plays via rzk), `selftest.mjs` (Content fallback intact), and `loadtest.mjs` (loads + plays `game.json` inside wasm).
