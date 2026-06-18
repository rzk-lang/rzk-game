# Goal/context-matched hints

Create the PR: https://github.com/rzk-lang/rzk-game/pull/new/phase5-hints

Adds authored hints to levels. A level may carry an ordered `hints:` list in its front-matter, each entry `{ text, when-goal? }`. On a puzzle page a new **Hints** panel sits below the result, hidden by default.

Two kinds of hint, handled differently so a goal-specific hint never shows out of context:

- a **plain** hint (no `when-goal`) is revealed one at a time by the **Show a hint** button;
- a **contextual** hint (with a `when-goal`) is shown only once the player has asked for a hint and its trigger is an infix of the focused hole's rendered goal — it is never reachable by the manual reveal, so it appears exactly while it is relevant and disappears when the goal moves on.

Matching is a deliberately simple case-sensitive infix test on the already-rendered goal, not structural unification, so an author can reason about it from the goal panel. The reveal count lives in the model only (a per-session affordance, reset on navigation), so no `localStorage` key is added and the export/import set is unchanged.

The two opening levels carry demo hints — each pairing a plain hint with a contextual one tied to a goal the player leaves behind after one refine — so the feature is live in the built-in game.

The reveal policy is a pure `visibleHints` in `RzkGame.Level`, unit-tested for the cases that matter (nothing before asking; the plain plus the matching contextual hint on asking; the contextual hint hiding once the goal no longer matches; the manual reveal never surfacing it out of context). The existing whole-game round-trip pins that the `game/` front-matter reproduces the model, and the suite also checks each demo level's `when-goal` fires on the real rzk goal and stops firing after a refine.
