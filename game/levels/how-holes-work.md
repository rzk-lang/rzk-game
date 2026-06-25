---
id: how-holes-work
title: How holes work
---

You play this game by filling **holes**. A hole is written `?`. It marks an unfilled part of a proof. Wherever you leave a `?`, the game works out what belongs there and shows it to you.

**The focused hole.** The first hole in a proof is *focused*. Its **goal** and **context** appear beside the editor. The goal is the type the hole must have. The context lists the term variables, cube variables, and tope assumptions in scope there. You fill the goal using what the context gives you.

**Moves.** The **Moves** panel offers tap-to-fill steps for the focused hole. Each step is read from the goal's type, not guessed. There are two kinds. An *introduction* builds a value of the goal from its shape: a $\lambda$ for a function, a pair for a $\Sigma$, `refl` for a reflexive path, or a tope constructor. A *give* applies something already in scope, such as a hypothesis or a lemma the level grants. It leaves fresh holes for the arguments.

Tapping a move drops it onto the focused hole. Any holes it introduces become the next ones to fill. You can also type into the editor directly.

**Check, Format, Undo.** **Check** type-checks your proof and refreshes the holes. **Format** tidies your text into rzk's canonical layout. **Undo** steps back through your edits, including tapped moves.

A level is solved when the editor type-checks with **no holes left** and the goal has the required type.
