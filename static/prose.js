// Render level prose to HTML: Markdown (via marked) with TeX math (via KaTeX).
//
// Math is delimited $...$ (inline) and $$...$$ (display). We stash the math
// segments behind placeholders before running Markdown, so Markdown never
// mangles TeX (e.g. underscores or backslashes), then substitute the
// KaTeX-rendered HTML back in afterwards. Exposed as globalThis.renderProse and
// called from the wasm app (see Main.hs js_renderProse) once per level load.
(function () {
  function renderProse(src) {
    if (!src) return "";
    var math = [];
    var stash = function (tex, display) {
      math.push({ tex: tex, display: display });
      return "@@RZKMATH" + (math.length - 1) + "@@";
    };
    var s = String(src)
      .replace(/\$\$([\s\S]+?)\$\$/g, function (_, tex) { return stash(tex, true); })
      .replace(/\$([^\$\n]+?)\$/g, function (_, tex) { return stash(tex, false); });

    var html = (globalThis.marked ? globalThis.marked.parse(s) : s);

    html = html.replace(/@@RZKMATH(\d+)@@/g, function (_, i) {
      var m = math[+i];
      try {
        return globalThis.katex.renderToString(m.tex, {
          displayMode: m.display,
          throwOnError: false,
        });
      } catch (e) {
        return m.tex;
      }
    });
    return html;
  }

  globalThis.renderProse = renderProse;
})();
