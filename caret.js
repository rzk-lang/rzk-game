// Put the caret back where the input method left it.
//
// The editor is a controlled textarea: miso owns its value, so when the input
// method rewrites the text (turning "\to " into "→ ") the browser re-renders the
// value and drops the caret at the end. The update function knows the offset the
// caret should have, and calls this once the patch has landed.
//
// The rAF is what waits for that patch: the update returns before miso has
// touched the DOM, so setting the selection synchronously would set it on the
// pre-rewrite text and be overwritten a frame later.
globalThis.setEditorCaret = function (offset) {
  requestAnimationFrame(function () {
    const el = document.querySelector("textarea.editor");
    if (!el) return;
    const i = Math.max(0, Math.min(Number(offset) || 0, el.value.length));
    el.focus();
    el.setSelectionRange(i, i);
  });
};
