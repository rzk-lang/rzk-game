# PR brief — make rzk's wasm build first-class (`build-type: Simple` + parser drift-guard)

Handoff for a **separate session in `rzk-lang/rzk`**. This change belongs upstream
in rzk (it benefits the LSP, the CLI, and Hackage installs, not just the game),
and must be validated against rzk's own CI. Authoring it from the game repo is
out of scope on purpose — see [`../../roadmap-1.md`](../../roadmap-1.md) §4, §9.

## Goal

Let any consumer (including `rzk-game`) depend on the `rzk` library under the
**GHC WebAssembly backend** without patching it. Today wasm-buildability is a
CI-time source mutation (`.github/workflows/wasm.yml`); make it a property of the
package instead.

## Why this is needed (and useful beyond the game)

- **The GHC WASM backend cannot run a `Custom` `Setup.hs`** — cabal compiles
  Setup to a `.wasm` module and then cannot execute it. So `build-type: Custom`
  is *fundamentally* incompatible with the wasm backend, regardless of what Setup
  does. `Simple` is the only fix.
- **It also removes BNFC/alex/happy from normal installs.** Today installing rzk
  (e.g. from Hackage) requires building **BNFC** (heavy), `alex`, and `happy` as
  build tools. With `Simple` + committed generated modules, none are needed to
  build rzk — faster, lighter installs for everyone, and the LSP/CLI lanes are
  unaffected.
- **Windows already relies on committed generated files.** The current
  `Setup.hs` guards regeneration with `#ifndef mingw32_HOST_OS`, so Windows
  builds already use the committed `Lex.hs`/`Par.hs`. This change just makes all
  platforms behave like the Windows path, with CI guaranteeing the committed
  files stay correct.

## Current state (pristine `rzk-lang/rzk@develop`)

- `rzk/rzk.cabal`: `build-type: Custom`; a `custom-setup` stanza; **four**
  `build-tool-depends` blocks (library, `executable rzk`, and the two test
  suites), each pulling `BNFC:bnfc`, `alex:alex`, `happy:happy`.
- `rzk/Setup.hs`: on `postConf` and `preBuild` (non-Windows) runs:
  ```
  bnfc -d -p Language.Rzk --generic --functor --text-token -o src/ grammar/Syntax.cf
  alex --ghc src/Language/Rzk/Syntax/Lex.x
  happy --array --info --ghc --coerce src/Language/Rzk/Syntax/Par.y
  ```
  So the **source of truth is `rzk/grammar/Syntax.cf`**; from it BNFC generates
  `src/Language/Rzk/Syntax/{Abs,Lex.x,Par.y,Print,Layout,ErrM,Skel,Test}.hs`,
  then alex/happy generate `Lex.hs`/`Par.hs` (+ `Par.info`). **All of these are
  already committed.**
- `.github/workflows/wasm.yml`: mutates the source in-CI (rm `Lex.x`/`Par.y`,
  `Custom`→`Simple`, strip `build-tool-depends`) before building. This PR makes
  that mutation step unnecessary.
- `.github/workflows/ghcjs.yml`: has an analogous "remove lexer/parser generator
  files" step that can likely be simplified too.

## The change

1. **`rzk/rzk.cabal`:**
   - `build-type: Custom` → `build-type: Simple`.
   - Remove the `custom-setup` stanza.
   - Remove all four `build-tool-depends` blocks (BNFC/alex/happy). They are only
     needed to *regenerate* the parser, which is now out-of-band (step 3).
   - Ensure the committed generated modules are shipped in sdist (they are
     regular modules under `hs-source-dirs: src`, so they are — but verify with
     `cabal sdist`). Keep `grammar/Syntax.cf` and the `.x`/`.y` in the tree
     (needed by the regen target and the guard); add to `extra-source-files` if
     not already shipped.
2. **Delete `rzk/Setup.hs`** (no longer used by `Simple`).
3. **Add an out-of-band regeneration target.** A cabal *flag* cannot do this —
   `Simple` has no build hook — so it must be a script / Makefile target run by
   developers who edit the grammar and by CI. Reconcile/replace the stale
   `rzk/Makefile` `syntax` target with one canonical target, e.g.
   `make regen-parser`, that runs exactly the three commands above (BNFC → alex →
   happy) and reproduces the committed file set (mind any post-BNFC cleanup such
   as removing `Test.hs`, so the tree matches what is committed). Document it in
   `CONTRIBUTING`/`README`: "edit `grammar/Syntax.cf`, then `make regen-parser`".
4. **Add the CI drift-guard** (the condition for accepting `Simple`). New lane
   that installs BNFC/alex/happy, regenerates from `grammar/Syntax.cf`, and fails
   if the result differs from what is committed:
   ```yaml
   name: Parser up-to-date (grammar drift guard)
   on: { push: { branches: [main, develop] }, pull_request: { branches: [develop] } }
   jobs:
     check-generated-parser:
       runs-on: ubuntu-latest
       steps:
         - uses: actions/checkout@v4
         - uses: haskell-actions/setup@v2
           with: { ghc-version: '9.6', cabal-version: 'latest' }
         - name: Install BNFC, alex, happy
           run: cabal install BNFC alex happy --overwrite-policy=always
         - name: Regenerate parser from grammar/Syntax.cf
           run: make -C rzk regen-parser   # or the canonical target from step 3
         - name: Fail if committed parser drifted from the grammar
           run: git diff --exit-code -- rzk/src/Language/Rzk/Syntax
   ```
   (Pin tool versions to the floors the old `build-tool-depends` used: BNFC
   ≥2.9.6.2, alex ≥3.2.4, happy ≥1.19.9 — different BNFC versions can produce
   different output, so pin exactly to avoid false drift.)
5. **Simplify `wasm.yml`** to just build (`wasm32-wasi-cabal build rzk:lib:rzk
   --flags=-lsp`) — drop the "Adapt the package" mutation step. Check whether
   `ghcjs.yml` can drop its file-removal step too.
6. **CHANGELOG** entry.

## Validation checklist (run in the rzk repo)

- `cabal build all` (normal GHC) — library, `executable rzk`, tests.
- `cabal test` / doctests (rzk uses doctest-parallel) — green.
- `+lsp` build still works (default flag is on).
- GHCJS / `rzk-js` build (the `nix develop .#ghcjs build-rzk-js` path) — still
  builds the playground.
- wasm lane (simplified) — `wasm32-wasi-cabal build rzk:lib:rzk --flags=-lsp`.
- The new drift-guard passes on a clean checkout, and **fails** if you tweak
  `grammar/Syntax.cf` without regenerating (sanity-check the guard actually
  guards).
- `cabal sdist` → unpack in isolation → `cabal build` **without** BNFC/alex/happy
  on PATH, to confirm Hackage installs no longer need the generators.

## Risks / notes

- **BNFC output stability.** The guard only works if the pinned BNFC/alex/happy
  reproduce the committed files byte-for-byte. Pin exact versions; if BNFC output
  is not perfectly reproducible across patch versions, pin to one and bump
  deliberately.
- **`Par.info`** (from `happy --info`) is committed; the regen target must pass
  `--info` so the guard's diff stays clean (or drop `Par.info` from the repo and
  from the diff scope).
- **Contributor workflow change.** Editing the grammar now requires running
  `make regen-parser` and committing the result; the guard enforces it. Call this
  out in the PR description and `CONTRIBUTING`.
- This is independent of the holes / structured-diagnostics / goal-query work
  (roadmap §4); it is the prerequisite that lets `rzk-game` pin rzk cleanly. Land
  it first.

## After this lands

`rzk-game` drops the spike's local-path pin + hand-mutation and depends on rzk as
a normal `source-repository-package` (a commit) with `flags: -lsp`. See
[`cabal.project`](./cabal.project) and [`NOTES.md`](./NOTES.md).
