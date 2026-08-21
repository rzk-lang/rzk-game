// Put the caret back where the input method left it.
//
// The editor is a controlled textarea: miso owns its value, so when the input
// method rewrites the text (turning "\to " into "→ ") the browser re-renders the
// value and drops the caret at the end. The update function knows the offset the
// caret should have, and calls this once the patch has landed.
//
// Waiting for that patch is the whole difficulty. miso diffs inside an animation
// frame of its own, queued after the one this call could take, and assigning
// .value moves the caret to the end — so setting the selection a frame too early
// is silently undone. Rather than guess the ordering, wait until the textarea
// actually holds the text the caret offset refers to, then place it.
//
// The bound on retries keeps a mismatch (an edit that arrived meanwhile, say)
// from spinning forever; giving up leaves the caret where the browser put it.
globalThis.setEditorCaret = function (offset, expected) {
  let tries = 0;
  const place = function () {
    const el = document.querySelector("textarea.editor");
    if (!el) return;
    if (el.value !== expected && tries < 10) {
      tries++;
      requestAnimationFrame(place);
      return;
    }
    const i = Math.max(0, Math.min(Number(offset) || 0, el.value.length));
    el.focus();
    el.setSelectionRange(i, i);
  };
  requestAnimationFrame(place);
};
