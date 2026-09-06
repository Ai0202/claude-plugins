// dom-snapshot.js — 実装画面の「見えている要素」を Figma と比べやすい形で JSON にする
// ブラウザ MCP(Claude in Chrome の javascript_tool / Playwright の browser_evaluate)でページ上で実行する。
// 返り値は JSON 文字列。要素ごとに: 深さ / タグ / role / 文言 / alt・aria-label・placeholder / 位置とサイズ /
// フォント(size/lineHeight weight family) / 文字色 / 背景色 / ボーダー / 角丸 / パディング / gap
// 画面の一部だけ見るときは末尾の walk(document.body, 0) の document.body をセレクタで差し替える。
(() => {
  const SKIP = new Set(['SCRIPT', 'STYLE', 'NOSCRIPT', 'TEMPLATE', 'META', 'LINK', 'HEAD']);
  const INTERACTIVE = new Set(['a', 'button', 'input', 'select', 'textarea', 'img', 'svg', 'video']);
  const px = (v) => Math.round(parseFloat(v) || 0);
  const hex = (c) => {
    const m = c && c.match(/\d+(\.\d+)?/g);
    if (!m || m.length < 3) return c;
    if (m.length >= 4 && parseFloat(m[3]) === 0) return 'transparent';
    const h = '#' + m.slice(0, 3).map((n) => (+n).toString(16).padStart(2, '0')).join('').toUpperCase();
    return m.length >= 4 && parseFloat(m[3]) < 1 ? `${h} a=${m[3]}` : h;
  };
  const out = [];
  const walk = (el, depth) => {
    if (SKIP.has(el.tagName)) return;
    const cs = getComputedStyle(el);
    if (cs.display === 'none' || cs.visibility === 'hidden' || parseFloat(cs.opacity) === 0) return;
    const r = el.getBoundingClientRect();
    if (r.width === 0 && r.height === 0) return;
    const tag = el.tagName.toLowerCase();
    const own = Array.from(el.childNodes)
      .filter((n) => n.nodeType === 3)
      .map((n) => n.textContent.replace(/\s+/g, ' ').trim())
      .filter(Boolean)
      .join(' ');
    const role = el.getAttribute('role') || undefined;
    if (own || INTERACTIVE.has(tag) || role) {
      const pad = [cs.paddingTop, cs.paddingRight, cs.paddingBottom, cs.paddingLeft].map(px);
      out.push({
        d: depth,
        tag,
        role,
        text: own || undefined,
        label: el.getAttribute('aria-label') || el.getAttribute('alt') || el.getAttribute('placeholder') || el.getAttribute('title') || undefined,
        href: tag === 'a' ? el.getAttribute('href') || undefined : undefined,
        type: tag === 'input' ? el.getAttribute('type') || 'text' : undefined,
        disabled: el.disabled || el.getAttribute('aria-disabled') === 'true' || undefined,
        box: [px(r.x + scrollX), px(r.y + scrollY), px(r.width), px(r.height)],
        font: own ? `${px(cs.fontSize)}/${px(cs.lineHeight)} ${cs.fontWeight} ${cs.fontFamily.split(',')[0].replace(/"/g, '')}` : undefined,
        color: own ? hex(cs.color) : undefined,
        bg: cs.backgroundColor !== 'rgba(0, 0, 0, 0)' ? hex(cs.backgroundColor) : undefined,
        border: cs.borderTopWidth !== '0px' && cs.borderTopStyle !== 'none' ? `${cs.borderTopWidth} ${hex(cs.borderTopColor)}` : undefined,
        radius: cs.borderRadius !== '0px' ? cs.borderRadius : undefined,
        pad: pad.some(Boolean) ? pad.join(' ') : undefined,
        gap: cs.gap && cs.gap !== 'normal' && cs.gap !== '0px' ? cs.gap : undefined,
      });
    }
    for (const c of el.children) walk(c, depth + 1);
  };
  walk(document.body, 0);
  const clean = (o) => Object.fromEntries(Object.entries(o).filter(([, v]) => v !== undefined));
  return JSON.stringify({ url: location.href, viewport: [innerWidth, innerHeight], count: out.length, elements: out.map(clean) });
})();
