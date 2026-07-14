/* Jackie Lives — dialogue editor front end. Vanilla JS, no build step. */

'use strict';

// ---------------------------------------------------------------- state

var MODEL = null;          // { groups, files, stats, warnings }
var EDITS = new Map();     // field.id -> { file, start, end, value }
var ORIG = new Map();      // field.id -> original value
var CUR = null;            // selected section
var SEL = null;            // selected line/choice object (tree view)

var view = { x: 60, y: 40, k: 1 };
var layout = { nodes: {}, w: 0, h: 0 };

var $ = function (id) { return document.getElementById(id); };

function el(tag, cls, text) {
  var e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text != null) e.textContent = text;
  return e;
}

// ---------------------------------------------------------------- load

function load(keepSection) {
  return fetch('/api/dialogues')
    .then(function (r) { return r.json(); })
    .then(function (d) {
      if (d.error) throw new Error(d.error);
      MODEL = d;
      EDITS.clear();
      ORIG.clear();
      indexFields();
      renderNav();
      renderStats();
      var sec = keepSection && findSection(keepSection);
      select(sec || firstSection());
      markDirty();
      // a broken graph on disk (someone hand-edited the .lua) must be loud
      if ((d.graphErrors || []).length) {
        banner('bad', 'The dialogue on disk is BROKEN:\n' +
          d.graphErrors.map(function (e) { return '  • ' + e.msg; }).join('\n'));
      }
    })
    .catch(function (e) {
      banner('bad', 'Could not read the dialogue: ' + e.message);
    });
}

function eachField(fn) {
  MODEL.groups.forEach(function (g) {
    g.sections.forEach(function (s) {
      var lines = [];
      if (s.kind === 'tree') {
        s.nodes.forEach(function (n) {
          lines = lines.concat(n.lines, n.choices);
        });
      } else if (s.kind === 'pool') {
        s.columns.forEach(function (c) { lines = lines.concat(c.lines); });
        lines = lines.concat(s.titleFields || []);
      } else {
        lines = s.fields.slice();
      }
      lines.forEach(function (ln) { fn(ln, s); });
    });
  });
}

function fieldsOf(ln) {
  var out = [];
  if (ln.text) out.push(ln.text);
  if (ln.m) out.push(ln.m);
  (ln.textPool || []).forEach(function (p) { if (p) out.push(p); });
  return out;
}

function indexFields() {
  eachField(function (ln) {
    fieldsOf(ln).forEach(function (f) { ORIG.set(f.id, f.value); });
  });
}

function findSection(id) {
  var hit = null;
  MODEL.groups.forEach(function (g) {
    g.sections.forEach(function (s) { if (s.id === id) hit = s; });
  });
  return hit;
}

function firstSection() {
  return MODEL.groups[0] && MODEL.groups[0].sections[0];
}

function renderStats() {
  var s = MODEL.stats;
  $('stats').textContent =
    s.sections + ' groups · ' + s.nodes + ' nodes · ' + s.lines + ' lines' +
    (MODEL.luaVerifier ? ' · verified with ' + MODEL.luaVerifier
                       : ' · no lua on PATH (structural check only)');
}

// ---------------------------------------------------------------- sidebar

function sectionDirty(s) {
  var d = false;
  var check = function (ln) {
    fieldsOf(ln).forEach(function (f) { if (EDITS.has(f.id)) d = true; });
  };
  if (s.kind === 'tree') {
    s.nodes.forEach(function (n) { n.lines.forEach(check); n.choices.forEach(check); });
  } else if (s.kind === 'pool') {
    s.columns.forEach(function (c) { c.lines.forEach(check); });
    (s.titleFields || []).forEach(check);
  } else {
    s.fields.forEach(check);
  }
  return d;
}

function sectionCount(s) {
  var n = 0;
  if (s.kind === 'tree') return s.nodes.length + ' nodes';
  if (s.kind === 'pool') {
    s.columns.forEach(function (c) { n += c.lines.length; });
    return n + ' lines';
  }
  return s.fields.length + ' lines';
}

function renderNav() {
  var nav = $('nav');
  nav.innerHTML = '';
  var q = $('filter').value.trim().toLowerCase();

  MODEL.groups.forEach(function (g) {
    var items = g.sections.filter(function (s) {
      return !q || (g.npc + ' ' + s.title).toLowerCase().indexOf(q) >= 0;
    });
    if (!items.length) return;
    nav.appendChild(el('div', 'navgroup', g.npc));
    items.forEach(function (s) {
      var b = el('button', 'navitem');
      b.appendChild(document.createTextNode(s.title));
      b.appendChild(el('span', 'n', sectionCount(s)));
      if (CUR && CUR.id === s.id) b.classList.add('active');
      if (sectionDirty(s)) b.classList.add('hasdirty');
      b.onclick = function () { select(s); };
      nav.appendChild(b);
    });
  });
}

$('filter').oninput = renderNav;

// ---------------------------------------------------------------- select

function select(s) {
  if (!s) return;
  CUR = s;
  SEL = null;
  $('inspector').hidden = true;
  $('stage-title').textContent = s.title;
  $('stage-sub').textContent = s.subtitle || '';

  var tools = $('stage-tools');
  tools.innerHTML = '';
  var bits = [];
  bits.push('file: ' + (MODEL.files[s.file] || {}).name);
  if (s.kind === 'tree') bits.push('start node: ' + s.start);
  if (s.muteFallback) bits.push('muteFallback: unvoiced lines are silent');
  if (s.cooldownSeconds) bits.push('cooldown: ' + s.cooldownSeconds + 's');
  tools.appendChild(document.createTextNode(bits.join('  ·  ')));
  if (s.kind === 'tree') {
    var an = el('button', 'btn tiny', '+ Add node');
    an.onclick = function () { addNodeDialog(s); };
    tools.appendChild(an);
  }

  if (s.kind === 'tree') {
    $('listview').hidden = true;
    $('viewport').hidden = false;
    renderTree._touched = false;      // a fresh tree always starts fitted
    renderTree(s);
  } else {
    $('viewport').hidden = true;
    $('listview').hidden = false;
    renderList(s);
  }
  renderNav();
}

// ---------------------------------------------------------------- badges

function badges(ln) {
  var wrap = el('div', 'linebar');
  var any = false;
  if (ln.sfx) {
    wrap.appendChild(el('span', 'tag sfx', ln.sfx));
    any = true;
  }
  Object.keys(ln.meta || {}).forEach(function (k) {
    if (k === 'to' || k === 'action') return;
    wrap.appendChild(el('span', 'tag meta', k + ' ' + ln.meta[k]));
    any = true;
  });
  if (ln.textPool && ln.textPool.length) {
    wrap.appendChild(el('span', 'tag meta', 'textPool ×' + ln.textPool.length));
    any = true;
  }
  if (ln.kind === 'choice' && ln.action) {
    wrap.appendChild(el('span', 'tag action', ln.action));
    any = true;
  }
  return any ? wrap : null;
}

function valueOf(f) {
  if (!f) return '';
  return EDITS.has(f.id) ? EDITS.get(f.id).value : f.value;
}

function isDirty(ln) {
  return fieldsOf(ln).some(function (f) { return EDITS.has(f.id); });
}

// ---------------------------------------------------------------- tree view

function renderTree(s) {
  var host = $('nodes');
  host.innerHTML = '';
  var cards = {};

  s.nodes.forEach(function (n) {
    var card = el('div', 'node');
    if (n.isStart) card.classList.add('start');
    if (n.terminal) card.classList.add('terminal');

    var head = el('div', 'node-head');
    head.appendChild(el('span', 'node-key', n.key));
    if (n.isStart) head.appendChild(el('span', 'tag start', 'start'));
    if (n.terminal) head.appendChild(el('span', 'tag terminal', 'end'));
    if (n.action) head.appendChild(el('span', 'tag action', n.action));
    if (n.extra && n.extra.restaurantPicker) {
      head.appendChild(el('span', 'tag meta', '+ venue picker'));
    }
    card.appendChild(head);

    if (n.lines.length > 1) {
      card.appendChild(el('div', 'pooln', 'jackiePool — one at random'));
    }
    n.lines.forEach(function (ln) { card.appendChild(lineRow(ln, 'jline')); });

    n.choices.forEach(function (ch, ci) {
      var row = lineRow(ch, 'choice');
      var del = el('span', 'del', '\u00d7');
      del.title = 'Delete this reply option';
      del.onclick = function (ev) { ev.stopPropagation(); deleteChoice(s, n, ci, ch); };
      row.insertBefore(del, row.firstChild);
      var to = el('span', 'to', ch.to ? '→ ' + ch.to : '→ end');
      if (!ch.to) to.classList.add('end');
      else to.onclick = function (ev) { ev.stopPropagation(); jumpTo(ch.to); };
      row.insertBefore(to, row.firstChild);
      card.appendChild(row);
    });

    var tools = el('div', 'node-tools');
    var addc = el('button', 'btn tiny', '+ reply');
    addc.onclick = function () { addChoiceDialog(s, n); };
    tools.appendChild(addc);
    var deln = el('button', 'btn tiny danger', 'delete node');
    deln.onclick = function () { deleteNode(s, n); };
    tools.appendChild(deln);
    card.appendChild(tools);

    host.appendChild(card);
    cards[n.key] = card;
  });

  doLayout(s, cards);
  if (!renderTree._touched) home();      // start readable at the top-left, not zoomed out
  applyView();
}

/* Open a tree at a readable size, parked on the start node. "Fit" is the overview. */
function home() {
  view.k = 0.9;
  view.x = 10;
  view.y = 10;
  applyView();
}

function lineRow(ln, cls) {
  var row = el('div', cls);
  if (isDirty(ln)) row.classList.add('dirty');
  row.appendChild(el('span', 'txt', valueOf(ln.text) || (ln.textPool ? '(random from textPool)' : '(no text)')));
  if (ln.m) row.appendChild(el('span', 'mvar', 'Hermano: ' + valueOf(ln.m)));
  if (ln.cond) row.appendChild(el('span', 'cond', 'only shown if: ' + ln.cond));
  var b = badges(ln);
  if (b) row.appendChild(b);
  row.onclick = function () { inspect(ln, row); };
  ln._row = row;
  return row;
}

/* Left -> right by depth from `start`; branches spread downward. */
function doLayout(s, cards) {
  var COLW = 420, GAP = 26, PAD = 40;
  var byKey = {};
  s.nodes.forEach(function (n) { byKey[n.key] = n; });

  // depth = BFS distance from start (unreachable nodes go in their own column)
  var depth = {}, q = [];
  if (byKey[s.start]) { depth[s.start] = 0; q.push(s.start); }
  while (q.length) {
    var k = q.shift();
    byKey[k].choices.forEach(function (c) {
      if (c.to && byKey[c.to] && depth[c.to] === undefined) {
        depth[c.to] = depth[k] + 1;
        q.push(c.to);
      }
    });
  }
  var maxd = 0;
  Object.keys(depth).forEach(function (k) { maxd = Math.max(maxd, depth[k]); });
  s.nodes.forEach(function (n) {
    if (depth[n.key] === undefined) depth[n.key] = maxd + 1;   // orphans
  });

  var cols = {};
  s.nodes.forEach(function (n) {
    (cols[depth[n.key]] = cols[depth[n.key]] || []).push(n.key);
  });

  layout.nodes = {};
  var maxx = 0, maxy = 0;
  Object.keys(cols).sort(function (a, b) { return a - b; }).forEach(function (d) {
    var x = PAD + d * COLW;
    // order by the average y of the parents that point here (reduces crossings)
    cols[d].sort(function (a, b) {
      return (want(a) - want(b));
    });
    var y = PAD;
    cols[d].forEach(function (k) {
      var h = cards[k].offsetHeight;
      layout.nodes[k] = { x: x, y: y, h: h, w: cards[k].offsetWidth };
      cards[k].style.left = x + 'px';
      cards[k].style.top = y + 'px';
      y += h + GAP;
      maxy = Math.max(maxy, y);
    });
    maxx = Math.max(maxx, x + 340);
  });

  function want(key) {
    var ys = [], i = 0;
    s.nodes.forEach(function (p) {
      p.choices.forEach(function (c) {
        if (c.to === key && layout.nodes[p.key]) ys.push(layout.nodes[p.key].y);
      });
    });
    if (!ys.length) return 1e9;   // no placed parent -> to the bottom of the column
    var sum = 0;
    for (i = 0; i < ys.length; i++) sum += ys[i];
    return sum / ys.length;
  }

  layout.w = maxx + PAD;
  layout.h = maxy + PAD;
  drawEdges(s, cards);
}

function drawEdges(s, cards) {
  var svg = $('edges');
  svg.setAttribute('width', layout.w);
  svg.setAttribute('height', layout.h);
  var parts = [];

  s.nodes.forEach(function (n) {
    var from = layout.nodes[n.key];
    if (!from) return;
    n.choices.forEach(function (c) {
      var to = c.to && layout.nodes[c.to];
      if (!to) return;
      var row = c._row;
      var y1 = from.y + (row ? row.offsetTop + row.offsetHeight / 2 : from.h / 2);
      var x1 = from.x + from.w;
      var x2 = to.x;
      var y2 = to.y + 18;
      var back = x2 < x1;                       // a loop back to an earlier node
      var dx = Math.max(50, Math.abs(x2 - x1) * 0.45);
      var d = back
        ? 'M' + x1 + ',' + y1 +
          ' C' + (x1 + 70) + ',' + y1 +
          ' ' + (x2 - 70) + ',' + (y2 - 40) +
          ' ' + x2 + ',' + y2
        : 'M' + x1 + ',' + y1 +
          ' C' + (x1 + dx) + ',' + y1 + ' ' + (x2 - dx) + ',' + y2 + ' ' + x2 + ',' + y2;
      parts.push('<path d="' + d + '" fill="none" stroke="' +
        (back ? '#4a5766' : '#73eff0') + '" stroke-width="1.6" opacity="' +
        (back ? '.55' : '.75') + '"/>');
      parts.push('<circle cx="' + x2 + '" cy="' + y2 + '" r="3.5" fill="' +
        (back ? '#4a5766' : '#73eff0') + '"/>');
    });
  });
  svg.innerHTML = parts.join('');
}

function jumpTo(key) {
  var n = layout.nodes[key];
  if (!n) return;
  var vp = $('viewport').getBoundingClientRect();
  renderTree._touched = true;
  view.x = vp.width / 2 - (n.x + 170) * view.k;
  view.y = 120 - n.y * view.k;
  applyView();
  // flash the target
  var cards = $('nodes').querySelectorAll('.node');
  for (var i = 0; i < cards.length; i++) {
    if (cards[i].querySelector('.node-key').textContent === key) {
      cards[i].animate(
        [{ boxShadow: '0 0 0 3px #f8db4b' }, { boxShadow: '0 0 0 0 transparent' }],
        { duration: 900 });
    }
  }
}

// ---------------------------------------------------------------- pan / zoom

function applyView() {
  $('world').style.transform =
    'translate(' + view.x + 'px,' + view.y + 'px) scale(' + view.k + ')';
  $('zoomlabel').textContent = Math.round(view.k * 100) + '%';
}

function fit() {
  var vp = $('viewport').getBoundingClientRect();
  if (!layout.w || !vp.width) return;
  var k = Math.min((vp.width - 40) / layout.w, (vp.height - 40) / layout.h, 1);
  view.k = Math.max(0.15, Math.min(1, k));
  view.x = 20;
  view.y = 20;
  applyView();
}

(function () {
  var vp = $('viewport');
  var drag = null;

  vp.addEventListener('mousedown', function (e) {
    if (e.target.closest('.node')) return;       // let clicks through to lines
    drag = { x: e.clientX, y: e.clientY, vx: view.x, vy: view.y };
    vp.classList.add('panning');
  });
  window.addEventListener('mousemove', function (e) {
    if (!drag) return;
    view.x = drag.vx + (e.clientX - drag.x);
    view.y = drag.vy + (e.clientY - drag.y);
    applyView();
  });
  window.addEventListener('mouseup', function () {
    drag = null;
    vp.classList.remove('panning');
  });

  vp.addEventListener('wheel', function (e) {
    e.preventDefault();
    renderTree._touched = true;
    var r = vp.getBoundingClientRect();
    var mx = e.clientX - r.left, my = e.clientY - r.top;
    var k2 = view.k * Math.pow(0.999, e.deltaY * (e.ctrlKey ? 3 : 1.6));
    k2 = Math.max(0.15, Math.min(2.5, k2));
    view.x = mx - (mx - view.x) * (k2 / view.k);
    view.y = my - (my - view.y) * (k2 / view.k);
    view.k = k2;
    applyView();
  }, { passive: false });

  document.querySelectorAll('#zoomctl [data-zoom]').forEach(function (b) {
    b.onclick = function () {
      var z = b.dataset.zoom;
      if (z === 'fit') { renderTree._touched = false; fit(); return; }
      renderTree._touched = true;
      view.k = Math.max(0.15, Math.min(2.5, view.k * (z === 'in' ? 1.2 : 1 / 1.2)));
      applyView();
    };
  });
}());

// ---------------------------------------------------------------- inspector

function inspect(ln, row) {
  SEL = ln;
  document.querySelectorAll('.jline.sel, .choice.sel').forEach(function (r) {
    r.classList.remove('sel');
  });
  if (row) row.classList.add('sel');

  var insp = $('inspector');
  insp.hidden = false;
  $('insp-kind').textContent =
    ln.kind === 'choice' ? "V's choice" : 'Jackie — spoken line';

  var body = $('insp-body');
  body.innerHTML = '';

  if (ln.text) {
    body.appendChild(editor(ln.text, 'Husbando  ·  female V  (the base line)', false, ln));
  }
  if (ln.m) {
    body.appendChild(editor(ln.m, 'Hermano  ·  male V  (the `m` variant)', true, ln));
  } else if (ln.text && ln.kind !== 'choice') {
    var n = el('div', 'insp-sec');
    n.appendChild(el('div', 'note',
      'No Hermano (`m`) variant on this line — it is reused as-is for a male V. ' +
      'Adding one means editing the .lua by hand; this tool only edits text that ' +
      'already exists.'));
    body.appendChild(n);
  }

  if (ln.textPool && ln.textPool.length) {
    var ps = el('div', 'insp-sec');
    ps.appendChild(el('label', null, 'textPool — one shown at random'));
    ln.textPool.forEach(function (p, i) {
      ps.appendChild(editorBox(p, ln, 'variant ' + (i + 1)));
    });
    body.appendChild(ps);
  }

  // where a reply leads (editable) -- only meaningful inside a tree
  if (ln.kind === 'choice' && CUR && CUR.kind === 'tree' && ln.addr) {
    body.appendChild(toSection(ln));
  }

  // the voice clip: editable, with the real transcript + a mismatch warning
  if (ln.addr && CUR && CUR.kind === 'tree') {
    body.appendChild(sfxSection(ln, null));
    if (ln.m) body.appendChild(sfxSection(ln, 'm'));
  } else {
    var meta = el('div', 'insp-sec');
    meta.appendChild(el('label', null, 'Voice clip (read-only here)'));
    meta.appendChild(el('div', ln.sfx ? 'ro' : 'ro muted',
      ln.sfx || 'no sfx — text only'));
    if (ln.clip && ln.clip.transcript) {
      var tr = el('div', 'transcript' +
        (ln.clip.match !== null && ln.clip.match < 0.6 ? ' bad' : ''));
      tr.appendChild(el('b', null, 'the clip actually says'));
      tr.appendChild(document.createTextNode('“' + ln.clip.transcript + '”'));
      meta.appendChild(tr);
    }
    body.appendChild(meta);
  }

  var keys = Object.keys(ln.meta || {});
  if (keys.length || ln.to !== undefined || ln.poolKey) {
    var m = el('div', 'insp-sec');
    m.appendChild(el('label', null, 'Metadata (read-only)'));
    var bs = el('div', 'badges');
    if (ln.poolKey) bs.appendChild(el('span', 'tag sfx', 'replaces ' + ln.poolKey));
    if (ln.kind === 'choice') {
      bs.appendChild(el('span', 'tag ' + (ln.to ? 'action' : 'meta'),
        ln.to ? 'to → ' + ln.to : 'to = nil (ends)'));
    }
    keys.forEach(function (k) {
      if (k === 'to') return;
      bs.appendChild(el('span', 'tag meta', k + ' = ' + ln.meta[k]));
    });
    m.appendChild(bs);
    body.appendChild(m);
  }
}

function editor(f, label, isM, ln) {
  var sec = el('div', 'insp-sec');
  sec.appendChild(el('label', null, label));
  sec.appendChild(editorBox(f, ln, null, isM));
  if (f.concat) {
    sec.appendChild(el('div', 'note',
      'In the .lua this is several strings joined with `..`. Saving rewrites it ' +
      'as one line — same text, still valid Lua.'));
  }
  return sec;
}

function editorBox(f, ln, ph, isM) {
  var ta = el('textarea', 'edit' + (isM ? ' m' : ''));
  ta.value = valueOf(f);
  if (ph) ta.placeholder = ph;
  if (EDITS.has(f.id)) ta.classList.add('dirty');
  ta.rows = Math.min(14, Math.max(2, Math.ceil(ta.value.length / 46)));
  ta.oninput = function () {
    setEdit(f, ta.value);
    ta.classList.toggle('dirty', EDITS.has(f.id));
    refreshRow(ln);
  };
  return ta;
}

function setEdit(f, value) {
  if (value === ORIG.get(f.id)) EDITS.delete(f.id);
  else EDITS.set(f.id, { file: f.file, start: f.start, end: f.end, value: value });
  markDirty();
}

function refreshRow(ln) {
  if (!ln || !ln._row) return;
  var row = ln._row;
  var txt = row.querySelector('.txt');
  if (txt) txt.textContent = valueOf(ln.text) || (ln.textPool ? '(random from textPool)' : '(no text)');
  var mv = row.querySelector('.mvar');
  if (mv && ln.m) mv.textContent = 'Hermano: ' + valueOf(ln.m);
  row.classList.toggle('dirty', isDirty(ln));
  if (CUR && CUR.kind === 'tree') {
    // heights may have changed -> relayout so the edges stay attached
    var cards = {};
    var els = $('nodes').querySelectorAll('.node');
    CUR.nodes.forEach(function (n, i) { cards[n.key] = els[i]; });
    doLayout(CUR, cards);
  }
  renderNav();
}

$('insp-close').onclick = function () { $('inspector').hidden = true; };

// ---------------------------------------------------------------- list view

function renderList(s) {
  var host = $('listview');
  host.innerHTML = '';

  if (s.titleFields) {
    s.titleFields.forEach(function (f) { host.appendChild(fieldCard(f)); });
  }

  if (s.kind === 'fields') {
    s.fields.forEach(function (f) { host.appendChild(fieldCard(f)); });
    return;
  }

  var cols = el('div', 'cols');
  s.columns.forEach(function (c) {
    var col = el('div', 'col');
    col.appendChild(el('h2', null, c.title + ' — ' + c.lines.length));
    c.lines.forEach(function (ln, i) {
      col.appendChild(lineCard(ln, i + 1));
    });
    cols.appendChild(col);
  });
  host.appendChild(cols);
}

function lineCard(ln, i) {
  var card = el('div', 'card');
  if (isDirty(ln)) card.classList.add('dirty');

  var lab = (ln.speaker ? ln.speaker + ' · ' : '') + (ln.poolKey ? ln.poolKey : i);
  card.appendChild(el('label', null, lab));

  if (ln.text) card.appendChild(inlineBox(ln, ln.text, card, false));
  if (ln.m) {
    card.appendChild(el('span', 'sub', 'Hermano (male V)'));
    card.appendChild(inlineBox(ln, ln.m, card, true));
  }
  var b = badges(ln);
  if (b) card.appendChild(b);
  return card;
}

function fieldCard(f) {
  var card = el('div', 'card');
  if (isDirty(f)) card.classList.add('dirty');
  card.appendChild(el('label', null, f.label));
  if (f.text) card.appendChild(inlineBox(f, f.text, card, false));
  if (f.m) {
    card.appendChild(el('span', 'sub', 'Hermano (male V)'));
    card.appendChild(inlineBox(f, f.m, card, true));
  }
  var bar = el('div', 'linebar');
  if (f.sfx) bar.appendChild(el('span', 'tag sfx', f.sfx));
  if (f.text && f.text.concat) bar.appendChild(el('span', 'tag meta', 'joined with ..'));
  if (bar.children.length) card.appendChild(bar);
  return card;
}

function inlineBox(ln, f, card, isM) {
  var ta = el('textarea', 'edit' + (isM ? ' m' : ''));
  ta.value = valueOf(f);
  if (EDITS.has(f.id)) ta.classList.add('dirty');
  ta.rows = Math.min(12, Math.max(2, Math.ceil(ta.value.length / 60)));
  ta.oninput = function () {
    setEdit(f, ta.value);
    ta.classList.toggle('dirty', EDITS.has(f.id));
    card.classList.toggle('dirty', isDirty(ln));
    renderNav();
  };
  return ta;
}

// ---------------------------------------------------------------- save

function markDirty() {
  var n = EDITS.size;
  $('save').disabled = n === 0;
  $('dirtycount').textContent = n ? n + ' unsaved ' + (n === 1 ? 'line' : 'lines') : '';
}

function banner(kind, msg) {
  var b = $('banner');
  b.hidden = false;
  b.className = 'banner ' + kind;
  $('banner-text').textContent = msg;
}
$('banner-x').onclick = function () { $('banner').hidden = true; };

$('save').onclick = function () {
  var edits = Array.from(EDITS.values());
  if (!edits.length) return;
  var hashes = {};
  Object.keys(MODEL.files).forEach(function (k) { hashes[k] = MODEL.files[k].hash; });

  $('save').disabled = true;
  $('save').textContent = 'Saving…';

  fetch('/api/save', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ edits: edits, hashes: hashes })
  })
    .then(function (r) { return r.json().then(function (j) { return [r.ok, j]; }); })
    .then(function (p) {
      var ok = p[0], d = p[1];
      $('save').textContent = 'Save all';
      if (!ok || !d.ok) {
        banner('bad', 'NOT SAVED — ' + (d.error || 'unknown error'));
        markDirty();
        return;
      }
      var lines = d.saved.map(function (r) {
        return r.file + ': ' + r.edits + ' line' + (r.edits === 1 ? '' : 's') +
          ' written, checked with ' + r.verifiedWith + '.';
      });
      var keep = CUR && CUR.id;
      return load(keep).then(function () {
        banner('ok', 'Saved. ' + lines.join('  ') +
          '  A backup of each file is in tools/dialogue-editor/backups/.');
      });
    })
    .catch(function (e) {
      $('save').textContent = 'Save all';
      banner('bad', 'NOT SAVED — ' + e.message);
      markDirty();
    });
};

$('reload').onclick = function () {
  if (EDITS.size && !confirm('Throw away ' + EDITS.size + ' unsaved edit(s)?')) return;
  var keep = CUR && CUR.id;
  load(keep).then(function () { banner('ok', 'Re-read the .lua files from disk.'); });
};

window.addEventListener('beforeunload', function (e) {
  if (EDITS.size) { e.preventDefault(); e.returnValue = ''; }
});

window.addEventListener('resize', function () {
  if (CUR && CUR.kind === 'tree' && !renderTree._touched) home();
});

load();

/* ==========================================================================
   STRUCTURAL EDITING
   ==========================================================================
   A structural change (add/delete a node or reply, set an sfx, repoint a `to`)
   is committed IMMEDIATELY as its own save, together with whatever text edits
   are still pending. That's deliberate:

     * the server applies text edits first (their byte offsets refer to the file
       as it was loaded) and then the op against a fresh parse, so the two can
       never race;
     * every structural change goes through the graph validator, so a broken
       tree is rejected before anything is written;
     * the page reloads from the file on disk afterwards, so what you see is
       always what's actually in config.lua. No stale offsets, no phantom queue.
   ========================================================================== */

function commit(ops, okMsg) {
  var hashes = {};
  Object.keys(MODEL.files).forEach(function (k) { hashes[k] = MODEL.files[k].hash; });

  return fetch('/api/save', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ edits: Array.from(EDITS.values()), ops: ops, hashes: hashes })
  })
    .then(function (r) { return r.json().then(function (j) { return [r.ok, j]; }); })
    .then(function (p) {
      var httpOk = p[0], d = p[1];
      if (!httpOk || !d.ok) {
        banner('bad', (d.error || 'Unknown error.'));
        return false;
      }
      var keep = CUR && CUR.id;
      return load(keep).then(function () {
        var msg = okMsg || 'Saved.';
        var warn = (d.graphWarnings || []).filter(function (w) {
          return w.msg.indexOf('UNREACHABLE') >= 0;
        });
        if (warn.length) {
          banner('warn', msg + '\n\nHeads up — ' + warn.length +
            ' node' + (warn.length === 1 ? ' is' : 's are') +
            ' now unreachable (nothing leads to them, so the player can never ' +
            'see them):\n' + warn.map(function (w) { return '  • ' + w.msg; }).join('\n'));
        } else {
          banner('ok', msg + '  Backup in tools/dialogue-editor/backups/.');
        }
        return true;
      });
    })
    .catch(function (e) { banner('bad', e.message); return false; });
}

/* ---------------- delete ---------------- */

function deleteChoice(sec, node, index, ch) {
  var txt = valueOf(ch.text) || '(no text)';
  if (!confirm('Delete this reply option?\n\n  "' + txt + '"\n' +
               (ch.to ? '  → ' + ch.to : '  (ends the conversation)') +
               '\n\nIf nothing else leads to "' + (ch.to || '') +
               '", that node becomes unreachable — you\'ll be warned, not blocked.')) return;
  commit([{ type: 'deleteChoice', ref: sec.ref, node: node.key, index: index }],
         'Deleted a reply option from "' + node.key + '".');
}

function deleteNode(sec, node) {
  if (!confirm('Delete the node "' + node.key + '" and everything in it?\n\n' +
               'This is refused if any reply still points at it.')) return;
  commit([{ type: 'deleteNode', ref: sec.ref, key: node.key }],
         'Deleted node "' + node.key + '".');
}

/* ---------------- modal plumbing ---------------- */

function modal(title, buildBody, onOk, okLabel) {
  var back = el('div');
  back.id = 'modal';
  var sheet = el('div', 'sheet');
  sheet.appendChild(el('h2', null, title));
  var body = el('div', 'body');
  var err = el('div', 'err');
  sheet.appendChild(body);
  var foot = el('div', 'foot');
  var cancel = el('button', 'btn ghost', 'Cancel');
  var okb = el('button', 'btn primary', okLabel || 'Add');
  foot.appendChild(cancel);
  foot.appendChild(okb);
  sheet.appendChild(foot);
  back.appendChild(sheet);

  var fields = buildBody(body);
  body.appendChild(err);

  function close() { back.remove(); }
  cancel.onclick = close;
  back.onclick = function (e) { if (e.target === back) close(); };
  document.addEventListener('keydown', function esc(e) {
    if (e.key === 'Escape') { close(); document.removeEventListener('keydown', esc); }
  });
  okb.onclick = function () {
    var problem = onOk(fields, close);
    if (problem) err.textContent = problem;
  };
  document.body.appendChild(back);
  var first = body.querySelector('input, textarea, select');
  if (first) first.focus();
  return { close: close, err: err };
}

function nodeOptions(sec, includeEnd, selected) {
  var sel = el('select');
  if (includeEnd) {
    var o = el('option', null, '— ends the conversation —');
    o.value = '';
    sel.appendChild(o);
  }
  sec.nodes.forEach(function (n) {
    var op = el('option', null, n.key + (n.isStart ? '  (start)' : ''));
    op.value = n.key;
    if (n.key === selected) op.selected = true;
    sel.appendChild(op);
  });
  return sel;
}

function labelled(body, text, ctrl, hint) {
  body.appendChild(el('label', null, text));
  body.appendChild(ctrl);
  if (hint) body.appendChild(el('div', 'hintline', hint));
  return ctrl;
}

/* ---------------- add reply ---------------- */

function addChoiceDialog(sec, node) {
  modal('Add a reply option to "' + node.key + '"', function (body) {
    var f = {};
    f.text = labelled(body, "V's line (what the player picks)",
                      el('textarea'), 'Silent text — V has no voice, so this is free to write.');
    f.to = labelled(body, 'Where it leads', nodeOptions(sec, true, null),
                    'Pick the node Jackie replies from, or end the conversation here.');
    f.m = labelled(body, 'Hermano variant — male V (optional)', el('textarea'),
                   'Leave blank if the line reads the same either way.');
    return f;
  }, function (f, close) {
    if (!f.text.value.trim()) return 'The reply needs some text.';
    close();
    commit([{ type: 'addChoice', ref: sec.ref, node: node.key,
              text: f.text.value.trim(), to: f.to.value || null,
              m: f.m.value.trim() || null }],
           'Added a reply option to "' + node.key + '".');
  });
}

/* ---------------- add node (linking is mandatory) ---------------- */

function addNodeDialog(sec) {
  modal('Add a node to "' + sec.title + '"', function (body) {
    var f = {};
    f.key = labelled(body, 'Node name', el('input'),
                     'Letters, numbers and underscores — e.g. mama_call. This is the ' +
                     'internal id, not something the player sees.');
    f.key.type = 'text';
    f.text = labelled(body, "Jackie's line", el('textarea'));
    f.sfx = labelled(body, 'Voice clip (optional)', el('input'),
                     'Leave empty and the line is text-only — and in a muteFallback ' +
                     'tree that means genuinely silent.');
    f.sfx.type = 'text';

    body.appendChild(el('label', null, '── How the player REACHES this node ──'));
    f.parent = labelled(body, 'Add a reply to this node…', nodeOptions(sec, false, null),
                        'A node nothing points at can never be seen in-game, so this ' +
                        'is required.');
    f.linkText = labelled(body, '…that reads', el('textarea'));

    body.appendChild(el('label', null, '── How the player LEAVES it (optional) ──'));
    f.outText = labelled(body, "V's reply", el('textarea'),
                         'Leave blank to make this a dead end that closes the conversation.');
    f.outTo = labelled(body, 'which leads to', nodeOptions(sec, true, sec.start));
    return f;
  }, function (f, close) {
    var key = f.key.value.trim();
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(key))
      return 'Node name must start with a letter and contain only letters, numbers and _.';
    if (!f.text.value.trim()) return "Jackie needs a line to say.";
    if (!f.linkText.value.trim()) return 'The reply that leads to the new node needs text.';
    close();
    commit([{ type: 'addNode', ref: sec.ref, key: key,
              text: f.text.value.trim(), sfx: f.sfx.value.trim() || null,
              link: { node: f.parent.value, mode: 'newChoice',
                      text: f.linkText.value.trim() },
              out: f.outText.value.trim()
                ? { text: f.outText.value.trim(), to: f.outTo.value || null }
                : null }],
           'Added node "' + key + '", reachable from "' + f.parent.value + '".');
  });
}

/* ---------------- the voice-clip picker ---------------- */

var CLIPS = null;

function clipPicker(onPick) {
  modal('Pick a voice clip', function (body) {
    var f = {};
    f.q = labelled(body, 'Search Jackie\'s real recorded lines', el('input'),
                   'These are the actual transcripts of his VO. Pick one and the ' +
                   'subtitle should match what it says.');
    f.q.type = 'text';
    f.list = el('div', 'cliplist');
    body.appendChild(f.list);

    function render() {
      var q = f.q.value.trim().toLowerCase();
      f.list.innerHTML = '';
      if (!CLIPS) { f.list.appendChild(el('div', 'hintline', 'Loading…')); return; }
      var hits = CLIPS.filter(function (c) {
        return !q || c.transcript.toLowerCase().indexOf(q) >= 0 ||
               c.id.toLowerCase().indexOf(q) >= 0;
      }).slice(0, 60);
      if (!hits.length) {
        f.list.appendChild(el('div', 'hintline', 'Nothing matches.'));
        return;
      }
      hits.forEach(function (c) {
        var d = el('div', 'clip');
        d.appendChild(el('div', 't', '“' + c.transcript + '”'));
        var i = el('div', 'i');
        i.appendChild(el('em', null, c.id));
        i.appendChild(document.createTextNode(c.male ? '   · male-V bank' : '   · female/unisex bank'));
        d.appendChild(i);
        d.onclick = function () { onPick(c.id); document.getElementById('modal').remove(); };
        f.list.appendChild(d);
      });
    }
    f.q.oninput = render;

    if (CLIPS) render();
    else {
      fetch('/api/clips').then(function (r) { return r.json(); }).then(function (d) {
        CLIPS = d.clips || [];
        render();
      });
      render();
    }
    return f;
  }, function (f, close) { close(); }, 'Close');
}

/* ---------------- inspector: sfx + `to` ---------------- */

function sfxSection(ln, variant) {
  var sec = el('div', 'insp-sec');
  sec.appendChild(el('label', null,
    variant === 'm' ? 'Hermano voice clip' : 'Voice clip (sfx)'));

  var row = el('div', 'sfxrow');
  var inp = el('input');
  inp.type = 'text';
  inp.placeholder = 'empty = text-only (silent)';
  inp.value = (variant === 'm' ? ln.sfxM : ln.sfx) || '';
  var pick = el('button', 'btn tiny', 'Pick…');
  var apply = el('button', 'btn tiny', 'Apply');
  row.appendChild(inp);
  row.appendChild(pick);
  row.appendChild(apply);
  sec.appendChild(row);

  var clip = variant === 'm' ? ln.clipM : ln.clip;
  if (clip) {
    var t = el('div', 'transcript');
    if (clip.missing) {
      t.className = 'transcript missing';
      t.appendChild(el('b', null, 'clip not found in transcripts.json'));
      t.appendChild(document.createTextNode(
        'This id has no transcript — it may be a typo, and a missing .wav makes ' +
        'Audioware reject the WHOLE bank (Jackie goes silent).'));
    } else {
      var poor = clip.match !== null && clip.match < 0.6;
      if (poor) t.className = 'transcript bad';
      t.appendChild(el('b', null, poor
        ? 'the clip does NOT say this — subtitle vs audio mismatch'
        : 'the clip actually says'));
      t.appendChild(document.createTextNode('“' + clip.transcript + '”'));
      sec.appendChild(t);
      t = null;
    }
    if (t) sec.appendChild(t);
  } else {
    sec.appendChild(el('div', 'note',
      'No clip — this line is text-only. In a muteFallback tree that means it is ' +
      'genuinely SILENT (no fallback grunt), so you can reword it freely.'));
  }

  function commitSfx(v) {
    commit([{ type: 'setField', ref: CUR.ref, addr: ln.addr, key: 'sfx',
              variant: variant || null, value: v }],
           v ? 'Voice clip set.' : 'Voice clip removed — the line is now text-only.');
  }
  pick.onclick = function () { clipPicker(function (id) { inp.value = id; commitSfx(id); }); };
  apply.onclick = function () { commitSfx(inp.value.trim()); };
  return sec;
}

function toSection(ln) {
  var sec = el('div', 'insp-sec');
  sec.appendChild(el('label', null, 'Where this reply leads'));
  var sel = nodeOptions(CUR, true, ln.to || '');
  sec.appendChild(sel);
  sel.onchange = function () {
    commit([{ type: 'setField', ref: CUR.ref, addr: ln.addr, key: 'to',
              value: sel.value }],
           sel.value ? 'Reply now leads to "' + sel.value + '".'
                     : 'Reply now ends the conversation.');
  };
  if (ln.cond) {
    sec.appendChild(el('div', 'note',
      'This reply is gated by a `cond` function — it only appears when that ' +
      'returns true. The function is code, so it is read-only here:'));
    sec.appendChild(el('div', 'cond', ln.cond));
  }
  return sec;
}
