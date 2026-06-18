---
id: associativity-intro
role: bridge-in
title: Start here
---

Once composition exists, the natural question is whether $(h \circ g) \circ f = h \circ (g \circ f)$. In a Segal type it is, by a slick argument due to Riehl and Shulman: the composition witnesses become arrows in the arrow type $\mathsf{arr}\,A$, which is *itself* Segal, so composing them builds a $3$-simplex (a tetrahedron) whose uniqueness forces both bracketings to agree.

*By the end you will be able to:* unfold a triangle into a square, lift composition into the arrow type, and extract the associativity tetrahedron and the triple composite. The witness-assembly level is marked ★ — the most clerical step, optional. We follow the [sHoTT chapter on associativity](https://rzk-lang.github.io/sHoTT/simplicial-hott/05-segal-types.rzk/#associativity).
