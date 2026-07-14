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
  if (s.cooldownSeconds) bits.push('cooldown: ' + s.cooldownSeconds + 's');
  tools.textContent = bits.join('  ·  ');

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

    n.choices.forEach(function (ch) {
      var row = lineRow(ch, 'choice');
      var to = el('span', 'to', ch.to ? '→ ' + ch.to : '→ end');
      if (!ch.to) to.classList.add('end');
      else to.onclick = function (ev) { ev.stopPropagation(); jumpTo(ch.to); };
      row.insertBefore(to, row.firstChild);
      card.appendChild(row);
    });

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

  // sfx / metadata
  var meta = el('div', 'insp-sec');
  meta.appendChild(el('label', null, 'Voice clip (read-only)'));
  if (ln.sfx) {
    meta.appendChild(el('div', 'ro', ln.sfx));
    meta.appendChild(el('div', 'note',
      'This line HAS real VO. Keep the subtitle matching what the clip actually says, ' +
      'or the audio and the text will disagree.'));
  } else {
    meta.appendChild(el('div', 'ro muted', 'no sfx — text only (mute + fallback grunt)'));
    meta.appendChild(el('div', 'note', 'Free to reword: nothing is spoken here.'));
  }
  if (ln.sfxM) {
    meta.appendChild(el('label', null, 'Hermano voice clip'));
    meta.appendChild(el('div', 'ro', ln.sfxM));
  }
  body.appendChild(meta);

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
