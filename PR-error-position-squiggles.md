# Diagnostics: squiggle the editable line an error points at

Create the PR: https://github.com/fizruk/rzk-game/pull/new/error-position-squiggles

Completes Phase 1's exit criterion. Clicking a hole already showed its goal and local context; the missing half was showing errors as squiggles. Type and parse errors now underline the editable line they point at, instead of only dumping text.

- `CheckResult` carries the editable-region line(s) of an error; `checkLevel` maps rzk's location (via `Rzk.Diagnostic`) back into the editable region.
- The editor overlay underlines the error line (`hl-errline`, wavy red); `highlightLines` tokenises per line, losslessly.
- rzk locations are line-level (no column), so the whole `#def` line is marked.

Tested: `make build` + `node selftest.mjs` pass (a type error maps to line 1); verified the underline in the browser.
