# Initial Ideas

## Main Idea

We want to create an engine to support interactive Rzk games, similar in the style to Lean4 games.

A particular goal in mind is to have the "∞-Yoneda Game" following Emily Riehl's [geodesic to Yoneda lemma](https://emilyriehl.github.io/yoneda/master/simplicial-hott/13-yoneda-geodesic.rzk/): a formalization of ∞-categorical Yoneda lemma in Rzk following a straight path, proving only necessary prerequisites.

Other source material for "games" is a 3 year old [Rzk demo for HoTT seminar at BMSTU](https://github.com/fizruk/bmstu-rzk-demo-2023).

Of course, we plan to develop new tutorials/games, possibly also including the recent modal extensions (but that's not the main concern at the moment).

## Game Specification

We think a game can easily be a collection of `*.rzk.md` files with a unifying config YAML,
setting up the structure of the game.

See [Lean4 Game's «Creating a new game»](https://github.com/leanprover-community/lean4game/blob/main/doc/create_game.md) to understand what kind of features we might need in Markdown and/or YAML.

## Compiling a Game

There are multiple ways to compile a game, roughly:

1. Build an interactive standalone website (HTML page) that relies on JS build of Rzk to check formalizations, and browser's local storage to save progress (and, optionally, allowing to export (and, ideally, import) an archive with user's formalizations).

2. Build an interactive VS Code extension (or as a part of current extension), that relies on Rzk language server and installed version of Rzk to check formalizations, and saves person's progress in a solution/ subdirectory of the repo (assuming the user has forked the game repository).

Ideally, one implementation that allows both would be perfect. One version to host on GitHub Pages, and, for a more smooth experience, cloning a game repo and playing locally (with a binary Rzk).

## Rzk UI/UX

To enable proper "game" experience (similar to Lean4 Games), Rzk should support at least

- typed holes
- proper display of typing context for (each) hole
- caching (not just in the language server) of checked modules (e.g. in a local .rzk/ subdir, or for the JS version, JSON-encoded cache hosted on GitHub Pages, somehow?)

It's possible that more is needed. But it would be better to keep Rzk changes to a minimum, for now.

## Implementation Choices

Only one consideration at the moment:

- I'm considering [miso](https://github.com/dmjio/miso) for the frontend of Rzk Games

## Context

Rzk's roadmap for the near future includes adding the following features to the Rzk language:

- definitely:
  - finalizing Islam's contribution on modalities: https://github.com/rzk-lang/rzk/pull/230
  - user-defined inductive types
  - module system
- possibly:
  - implicit arguments
  - user-defined higher-inductive types
  - n-truncations (maybe as user-defined HITs)
  - localizations à la <https://arxiv.org/abs/1706.07526>, at least for localization at Delta^1 or the (2,1)-horn inclusion

## Organization

Currently this repository is private under fizruk/rzk-game. After experiments, I plan to move it to rzk-lang. I envision the following repositories related to Rzk Games in the end:

- rzk-lang/rzk-game — the game engine (compiling Rzk game spec into an HTML app)
- rzk-lang/rzk-game-action — a GitHub Action to automatically build, check, and deploy the game (to GitHub Pages)
- rzk-lang/yoneda-game — the ∞-Yoneda game
- rzk-lang/rzk-game-template — template for an Rzk game spec
- (possibly) rzk-lang/vscode-rzk-game — a separate extension to support Rzk Game in VS Code
