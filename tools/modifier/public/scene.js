'use strict';
// 场景页：雨街的楼、地形、出生点、灯、前景、远层。改动都以“路径 → 值”存进 tuning.json，默认数据不动。
window.SceneEditor = (() => {
  const M = window.Modifier;
  const clone = v => JSON.parse(JSON.stringify(v));
  const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);
  const esc = v => String(v ?? '').replace(/[&<>"']/g, c => ({'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'}[c]));
  const round = v => Math.round(v * 10) / 10;
  const MODES = [['pieces', '楼'], ['terrain', '地形'], ['spawns', '出生点'], ['lamps', '灯'], ['foreground', '前景'], ['layers', '远层和雨']];
  const ART_SCALE = 2710 / 1672;      // 和 street_backdrop.gd 一致：成图 1 像素 = 多少世界单位
  const FLOORS = [[580, '地面'], [300, '二层'], [20, '三层'], [-260, '屋顶']];
  const STREET = 580, WATER = 665, BOTTOM = 826;
  const STYLES = ['balcony', 'ring', 'bridge', 'eave', 'gallery', 'cornice', 'ridge', 'steps', 'plank', 'stone', 'slab'];
  const STYLE_LABELS = {balcony: '阳台', ring: '钟楼环', bridge: '桥', eave: '屋檐', gallery: '廊道', cornice: '檐口', ridge: '屋脊', steps: '石阶', plank: '木栈道', stone: '石台', slab: '石板'};
  const FG_KINDS = [['pillar', '石柱'], ['lamp', '路灯剪影'], ['sign', '招牌']];
  const FIELD_OF = {platform: 'platforms', block: 'blocks', slope: 'slopes', spawn: 'spawns', lamp: 'lamps', fg: 'foreground'};
  const KIND_OF = {platforms: 'platform', blocks: 'block', slopes: 'slope'};
  const LINKED = ['platforms', 'blocks', 'slopes', 'lamps'];

  // 一条地形末尾的选项字典：off 没有这条；platform 的 solid、block 的 pass 决定挡不挡；bottom 实心到哪儿。
  const optAt = kind => kind === 'slope' ? 5 : 4;
  const optOf = (kind, row) => row?.[optAt(kind)] || {};
  const isOff = (kind, row) => !!optOf(kind, row).off;
  function setOpt(kind, row, key, value) {
    const at = optAt(kind), next = {...(row[at] || {})};
    if (value === undefined || value === false) delete next[key]; else next[key] = value;
    if (Object.keys(next).length) row[at] = next; else row.length = Math.min(row.length, at);
  }
  // pass 能跳穿；ground 实心到地面；part 实心到某个高度
  function modeOf(kind, row) {
    const o = optOf(kind, row);
    if (kind === 'slope') return o.solid ? 'ground' : 'pass';
    if (kind === 'platform') return !o.solid ? 'pass' : o.bottom >= STREET ? 'ground' : 'part';
    return o.pass ? 'pass' : o.bottom === undefined || o.bottom >= STREET ? 'ground' : 'part';
  }
  function lowOf(kind, row) {
    const mode = modeOf(kind, row);
    return mode === 'pass' ? null : mode === 'ground' ? STREET : optOf(kind, row).bottom ?? row[2] + 16;
  }
  function setMode(kind, row, mode) {
    if (kind === 'slope') { setOpt(kind, row, 'solid', mode === 'ground'); return; }
    for (const key of ['solid', 'pass', 'bottom']) setOpt(kind, row, key, undefined);
    if (kind === 'platform' && mode !== 'pass') setOpt(kind, row, 'solid', true);
    if (kind === 'block' && mode === 'pass') setOpt(kind, row, 'pass', true);
    if (mode === 'part') setOpt(kind, row, 'bottom', Math.min(row[2] + 60, STREET - 1));
    if (mode === 'ground' && kind === 'platform') setOpt(kind, row, 'bottom', STREET);
  }
  const slopeY = (row, x) => row[1] + (row[3] - row[1]) * (x - row[0]) / (row[2] - row[0]);
  // 平移一条数据。石台下沿跟着动，到地面的不动。
  function shiftRow(field, row, mx, my) {
    if (field === 'slopes') { row[0] = round(row[0] + mx); row[2] = round(row[2] + mx); row[1] = round(row[1] + my); row[3] = round(row[3] + my); return; }
    if (field === 'foreground') { row[0] = round(row[0] + mx); return; }
    if (field === 'lamps' || field === 'spawns') { row[0] = round(row[0] + mx); row[1] = round(row[1] + my); return; }
    row[0] = round(row[0] + mx); row[1] = round(row[1] + mx); row[2] = round(row[2] + my);
    const kind = KIND_OF[field], bottom = optOf(kind, row).bottom;
    if (bottom !== undefined && bottom < STREET) setOpt(kind, row, 'bottom', Math.min(round(bottom + my), STREET));
  }

  let ctx = null, root = null, canvas = null, page = null;
  const view = {section: 0, x: 780, y: 60, zoom: 0.14, mode: 'pieces', fitted: false, labels: true};
  let selected = null, live = null, drag = null, observer = null, spaceDown = false;
  const images = new Map();

  const defaults = () => ctx.state.defaults;
  const scene = () => ctx.state.scene;
  const pieces = () => Object.fromEntries(scene().pieces.map(p => [p.id, p]));
  const val = key => live && Object.hasOwn(live, key) ? live[key] : Object.hasOwn(ctx.values, key) ? ctx.values[key] : defaults()[key];
  const names = () => Object.keys(defaults()).filter(k => /^layout\/sections\/.+\/art$/.test(k)).map(k => k.split('/')[2]);
  const secKey = (field, index = view.section) => 'layout/sections/' + names()[index] + '/' + field;
  const planKey = (index = view.section) => 'scene/plan/' + index;
  const hasPlanEdit = (index = view.section) => (live && Object.hasOwn(live, planKey(index))) || Object.hasOwn(ctx.values, planKey(index));

  function save(changes, remember = true) {
    const next = clone(ctx.values);
    for (const [key, value] of Object.entries(changes)) {
      if (value === undefined || equal(value, defaults()[key])) delete next[key];
      else next[key] = clone(value);
    }
    ctx.commit(next, remember);
  }

  function image(url) {
    if (!url) return null;
    if (!images.has(url)) {
      const im = new Image();
      im.onload = () => { draw(); renderWarnings(); };
      im.src = url;
      images.set(url, im);
    }
    const im = images.get(url);
    return im.complete && im.naturalWidth ? im : null;
  }
  const texUrl = tex => '/scene-image?path=' + encodeURIComponent(String(tex).replace('res://', ''));

  // ---------------------------------------------------------------- 件和它带的地形
  function metaOf(item) { const p = pieces()[item.piece]; return p ? M.pieceMeta(p, item.mirror) : null; }
  function boxOf(item) {
    const meta = metaOf(item);
    if (!meta) return null;
    const left = item.x - meta.attach[0];
    return {left, right: left + meta.w, top: meta.top + item.y, bottom: meta.top + item.y + meta.h, attachL: item.x, attachR: left + meta.attach[1]};
  }
  function terrainOf(item) {
    const meta = metaOf(item), left = item.x - meta.attach[0], dy = item.y;
    return {
      platforms: meta.stand.map(([a, b, y, s]) => [round(left + a), round(left + b), Math.round((y + dy) * 100) / 100, s]),
      blocks: meta.blocks.map(([a, b, y, s]) => [round(left + a), round(left + b), Math.round((y + dy) * 100) / 100, s]),
      slopes: (meta.slopes || []).map(([a, ya, b, yb, s]) => [round(left + a), Math.round((ya + dy) * 100) / 100, round(left + b), Math.round((yb + dy) * 100) / 100, s]),
      lamps: meta.lamps.map(([x, y, k, r]) => [round(left + x), Math.round((y + dy) * 100) / 100, k, r]),
    };
  }
  // 这一件带来的平台、石台、斜坡、灯在当前地形里是哪几条（坐标对得上就算），对不上的是 -1。
  function matchRows(field, own) {
    const rows = val(secKey(field)), used = new Set(), n = field === 'lamps' ? 2 : field === 'slopes' ? 4 : 3;
    return own.map(row => {
      const hit = rows.findIndex((r, i) => !used.has(i) && row.slice(0, n).every((v, k) => Math.abs(r[k] - v) < 1));
      if (hit >= 0) used.add(hit);
      return hit;
    });
  }
  function linksOf(item) {
    const own = terrainOf(item), links = {};
    for (const field of LINKED) links[field] = matchRows(field, own[field]).filter(i => i >= 0);
    // 站在这一件台面上的出生点跟着它走
    const tops = [...links.platforms.map(i => val(secKey('platforms'))[i]), ...links.blocks.map(i => val(secKey('blocks'))[i])];
    const ramps = links.slopes.map(i => val(secKey('slopes'))[i]);
    links.spawns = val(secKey('spawns')).map(([x, y], i) => Math.abs(y - STREET) >= 1 && (tops.some(([a, b, s]) => x >= a && x <= b && Math.abs(s - y) < 2) || ramps.some(r => x >= r[0] && x <= r[2] && Math.abs(slopeY(r, x) - y) < 4)) ? i : -1).filter(i => i >= 0);
    return links;
  }
  // 按 links 把这一件带的各条挪 (mx, my)，返回要存的改动。base 是挪之前的数据。
  function movedLinks(links, mx, my, base = field => val(secKey(field))) {
    const out = {};
    for (const field of [...LINKED, 'spawns']) {
      const rows = clone(base(field));
      for (const i of links[field]) shiftRow(field, rows[i], mx, my);
      out[secKey(field)] = rows;
    }
    return out;
  }
  function withExtent(plan) {
    const boxes = plan.items.map(boxOf).filter(Boolean);
    if (!boxes.length) return plan;
    const out = clone(plan);
    out.x0 = Math.min(plan.x0, Math.floor(Math.min(...boxes.map(b => b.left))));
    out.x1 = Math.max(plan.x1, Math.ceil(Math.max(...boxes.map(b => b.right))));
    if (out.y0 !== undefined) out.y0 = Math.min(out.y0, Math.floor((Math.min(...boxes.map(b => b.top)) - 20) / 10) * 10);
    return out;
  }

  // ---------------------------------------------------------------- 画
  const sx = wx => (wx - view.x) * view.zoom + canvas.clientWidth / 2;
  const sy = wy => (wy - view.y) * view.zoom + canvas.clientHeight / 2;
  const wx = px => (px - canvas.clientWidth / 2) / view.zoom + view.x;
  const wy = px => (px - canvas.clientHeight / 2) / view.zoom + view.y;

  function drawTiles(g, im, scroll, top) {
    const info = scene(), origin = 2000 + info.arenaHalf + view.section * info.spacing;
    const cx = origin + view.x, tw = im.naturalWidth * ART_SCALE, th = im.naturalHeight * ART_SCALE;
    const base = cx * (1 - scroll) - origin, left = wx(0), right = wx(canvas.clientWidth);
    let u = Math.floor((left - base) / tw);
    for (let x = base + u * tw; x < right; x += tw, u++) {
      const flip = ((u % 2) + 2) % 2 === 1;
      g.save();
      g.translate(sx(flip ? x + tw : x), sy(top));
      g.scale(flip ? -view.zoom : view.zoom, view.zoom);
      g.drawImage(im, 0, 0, tw, th);
      g.restore();
    }
    return top + th;
  }
  function fogColor(im) {
    if (im.fog) return im.fog;
    const c = document.createElement('canvas');
    c.width = im.naturalWidth; c.height = 1;
    const g = c.getContext('2d', {willReadFrequently: true});
    g.drawImage(im, 0, -(im.naturalHeight - 1));
    const d = g.getImageData(0, 0, c.width, 1).data;
    let r = 0, gg = 0, b = 0, a = 0;
    for (let i = 0; i < d.length; i += 32) { const w = d[i + 3]; r += d[i] * w; gg += d[i + 1] * w; b += d[i + 2] * w; a += w; }
    im.fog = a ? 'rgb(' + r / a + ',' + gg / a + ',' + b / a + ')' : '#23304a';
    return im.fog;
  }
  function drawBackdrop(g, W, H) {
    g.fillStyle = '#23304a';
    g.fillRect(0, 0, W, H);
    const sky = image(texUrl(val('layout/backdrop/sky/tex')));
    if (sky) {
      // 和游戏一样：镜像平铺、几乎贴屏幕，高度和左右挪都按 720 高的游戏画面折算
      const k = H / 720, h = val('layout/backdrop/sky/screenH') * k, w = sky.naturalWidth * h / sky.naturalHeight;
      const scrolled = (2000 + scene().arenaHalf + view.section * scene().spacing + view.x) * val('layout/backdrop/sky/scroll') * k - val('layout/backdrop/sky/shift') * k;
      const period = 2 * w, off = ((scrolled % period) + period) % period;
      for (let x = -off, u = 0; x < W; x += w, u++) {
        g.save();
        g.translate(u % 2 ? x + w : x, -50 * k);
        g.scale(u % 2 ? -1 : 1, 1);
        g.drawImage(sky, 0, 0, w, h);
        g.restore();
      }
    }
    const far = image(texUrl(val('layout/backdrop/far/tex')));
    if (far) {
      // 和游戏一样：远景图下面接它下沿颜色的雾，矮的图会盖住一大片
      const bottom = sy(drawTiles(g, far, val('layout/backdrop/far/scroll'), val('layout/backdrop/far/top')));
      if (bottom < H) { g.fillStyle = fogColor(far); g.fillRect(0, Math.max(0, bottom), W, H - Math.max(0, bottom)); }
    }
    for (const row of val('layout/backdrop/depth')) {
      const im = image(texUrl(row.tex));
      if (im) drawTiles(g, im, row.scroll, row.bottom - im.naturalHeight * ART_SCALE);
    }
  }
  // 改过楼的段：停手一会儿后台出一张成图，有了就用它（光影和游戏里一样），没出好之前先看拼接预览。
  const previews = {};
  let previewTimer = null, previewBusy = false;
  function setBakeNote(on) { const el = root?.querySelector('.sc-bake'); if (el) el.hidden = !on; }
  function queuePreview(wait = 900) {
    clearTimeout(previewTimer);
    if (!root?.isConnected || !ctx.state.scene || !hasPlanEdit()) { setBakeNote(false); return; }
    if (previews[view.section]?.key === JSON.stringify(val(planKey()))) { setBakeNote(false); return; }
    setBakeNote(true);
    previewTimer = setTimeout(runPreview, wait);
  }
  async function runPreview() {
    if (drag || previewBusy) { queuePreview(); return; }
    const index = view.section, plan = val(planKey()), key = JSON.stringify(plan);
    previewBusy = true;
    try {
      const {art} = await ctx.api('/api/scene/bake', 'POST', {plan});
      previews[index] = {key, art};
      draw();
    } catch (error) {
      ctx.notify(error.message, true);
      previews[index] = {key, art: null};   // 同一份方案不反复重试
    }
    previewBusy = false;
    queuePreview();
  }
  function drawNear(g) {
    const plan = val(planKey()), baked = hasPlanEdit() && previews[view.section]?.key === JSON.stringify(plan) ? previews[view.section].art : null;
    const art = baked || val(secKey('art'));
    if ((baked || !hasPlanEdit()) && art.near) {
      const im = image(texUrl(art.near));
      if (im) {
        g.drawImage(im, sx(art.x0), sy(art.y0), art.width * view.zoom, art.width * im.naturalHeight / im.naturalWidth * view.zoom);
        return;
      }
    }
    // 拼接预览：出图时才有统一光影
    g.fillStyle = '#2a3040';
    g.fillRect(sx(plan.x0), sy(STREET - 6), (plan.x1 - plan.x0) * view.zoom, (WATER - STREET + 6) * view.zoom);
    g.fillStyle = '#111827';
    g.fillRect(sx(plan.x0), sy(WATER), (plan.x1 - plan.x0) * view.zoom, (BOTTOM - WATER) * view.zoom);
    for (const item of [...plan.items].sort((a, b) => a.z - b.z)) {
      const box = boxOf(item), p = pieces()[item.piece], im = p && image(p.url);
      if (!box || !im) continue;
      g.save();
      g.translate(sx(item.mirror ? box.right : box.left), sy(box.top));
      g.scale(item.mirror ? -1 : 1, 1);
      g.drawImage(im, 0, 0, (box.right - box.left) * view.zoom, (box.bottom - box.top) * view.zoom);
      g.restore();
    }
  }
  function drawWater(g, W, H) {
    const y = sy(WATER);
    if (y >= H) return;
    g.fillStyle = '#111827';
    g.fillRect(0, Math.max(0, y), W, H - Math.max(0, y));
  }
  const isSel = (kind, index) => selected && selected.kind === kind && selected.index === index;
  function label(g, text, x, y, color) {
    g.font = '12px "Microsoft YaHei UI", sans-serif';
    g.fillStyle = 'rgba(14,19,30,.78)';
    g.fillRect(x - 3, y - 12, g.measureText(text).width + 6, 16);
    g.fillStyle = color;
    g.fillText(text, x, y);
  }
  function drawGuides(g, W) {
    const half = scene().arenaHalf;
    g.lineWidth = 1;
    g.setLineDash([3, 5]);
    g.strokeStyle = 'rgba(190,205,230,.28)';
    for (const [y, name] of FLOORS) {
      g.beginPath(); g.moveTo(0, sy(y)); g.lineTo(W, sy(y)); g.stroke();
      if (view.labels) label(g, name, 6, sy(y) - 3, '#a9b6ca');
    }
    g.strokeStyle = 'rgba(233,184,114,.55)';
    for (const x of [-half, half]) { g.beginPath(); g.moveTo(sx(x), 0); g.lineTo(sx(x), canvas.clientHeight); g.stroke(); }
    g.setLineDash([]);
  }
  function drawOverlays(g) {
    const m = view.mode;
    const dim = active => { g.globalAlpha = active ? 1 : 0.28; };
    if (m === 'pieces') {
      val(planKey()).items.forEach((item, i) => {
        const b = boxOf(item);
        if (!b) return;
        g.lineWidth = isSel('piece', i) ? 2 : 1;
        g.strokeStyle = isSel('piece', i) ? '#e9b872' : 'rgba(228,233,241,.35)';
        g.strokeRect(sx(b.left), sy(b.top), (b.right - b.left) * view.zoom, (b.bottom - b.top) * view.zoom);
      });
    }
    dim(m === 'terrain');
    if (m === 'pieces' || m === 'terrain' || m === 'spawns') {
      // 金线能跳穿，紫块实心挡路，灰虚线是关掉了
      const grip = (x, y) => { g.fillStyle = '#ffd9a0'; g.fillRect(sx(x) - 4, sy(y) - 4, 8, 8); };
      for (const [kind, field] of [['block', 'blocks'], ['platform', 'platforms']]) val(secKey(field)).forEach((row, i) => {
        const [a, b, y] = row, on = isSel(kind, i), off = isOff(kind, row), low = lowOf(kind, row);
        g.setLineDash(off ? [7, 5] : []);
        if (low === null) {
          g.lineWidth = on ? 4 : 2.5;
          g.strokeStyle = on ? '#ffd9a0' : off ? 'rgba(210,218,232,.6)' : '#e9b872';
          g.beginPath(); g.moveTo(sx(a), sy(y)); g.lineTo(sx(b), sy(y)); g.stroke();
        } else {
          if (!off) { g.fillStyle = 'rgba(164,135,255,.22)'; g.fillRect(sx(a), sy(y), (b - a) * view.zoom, (low - y) * view.zoom); }
          g.lineWidth = on ? 3 : 1.5;
          g.strokeStyle = on ? '#ffd9a0' : off ? 'rgba(210,218,232,.6)' : '#a487ff';
          g.strokeRect(sx(a), sy(y), (b - a) * view.zoom, (low - y) * view.zoom);
        }
        g.setLineDash([]);
        if (on) { grip(a, y); grip(b, y); if (modeOf(kind, row) === 'part') grip((a + b) / 2, low); }
      });
      val(secKey('slopes')).forEach((row, i) => {
        const [a, ya, b, yb] = row, on = isSel('slope', i), off = isOff('slope', row), solid = modeOf('slope', row) === 'ground';
        if (solid && !off) {
          g.fillStyle = 'rgba(164,135,255,.22)';
          g.beginPath(); g.moveTo(sx(a), sy(ya)); g.lineTo(sx(b), sy(yb)); g.lineTo(sx(b), sy(STREET)); g.lineTo(sx(a), sy(STREET)); g.closePath(); g.fill();
        }
        g.setLineDash(off ? [7, 5] : []);
        g.lineWidth = on ? 4 : 2.5;
        g.strokeStyle = on ? '#ffd9a0' : off ? 'rgba(210,218,232,.6)' : solid ? '#a487ff' : '#e9b872';
        g.beginPath(); g.moveTo(sx(a), sy(ya)); g.lineTo(sx(b), sy(yb)); g.stroke();
        g.setLineDash([]);
        if (on) { grip(a, ya); grip(b, yb); }
      });
    }
    g.globalAlpha = 1;
    if (m === 'spawns') val(secKey('spawns')).forEach(([x, y], i) => {
      g.fillStyle = isSel('spawn', i) ? '#ffd9a0' : '#7fd1c7';
      g.beginPath(); g.moveTo(sx(x), sy(y)); g.lineTo(sx(x) - 7, sy(y) - 12); g.lineTo(sx(x) + 7, sy(y) - 12); g.closePath(); g.fill();
      label(g, String(i + 1), sx(x) - 4, sy(y) - 16, '#c9f0ea');
    });
    if (m === 'lamps') val(secKey('lamps')).forEach(([x, y, kind, reach], i) => {
      const head = kind === 'street' ? y - (reach || 150) : y;
      g.strokeStyle = g.fillStyle = isSel('lamp', i) ? '#ffd9a0' : '#ffc46b';
      g.lineWidth = 1.5;
      if (kind === 'street') { g.beginPath(); g.moveTo(sx(x), sy(y)); g.lineTo(sx(x), sy(head)); g.stroke(); }
      g.beginPath(); g.arc(sx(x), sy(head), isSel('lamp', i) ? 7 : 5, 0, 7); g.fill();
    });
    if (m === 'foreground') val(secKey('foreground')).forEach(([x, kind], i) => {
      g.strokeStyle = isSel('fg', i) ? '#ffd9a0' : '#9fb4d4';
      g.lineWidth = isSel('fg', i) ? 3 : 1.5;
      g.beginPath(); g.moveTo(sx(x), 26); g.lineTo(sx(x), canvas.clientHeight); g.stroke();
      label(g, (FG_KINDS.find(k => k[0] === kind) || [0, kind])[1], sx(x) + 4, 22, '#c9d6ea');
    });
    g.globalAlpha = 1;
  }
  function draw() {
    if (!canvas || !canvas.isConnected) return;
    const ratio = window.devicePixelRatio || 1, W = canvas.clientWidth, H = canvas.clientHeight;
    if (canvas.width !== Math.round(W * ratio) || canvas.height !== Math.round(H * ratio)) { canvas.width = Math.round(W * ratio); canvas.height = Math.round(H * ratio); }
    const g = canvas.getContext('2d');
    g.setTransform(ratio, 0, 0, ratio, 0, 0);
    g.imageSmoothingQuality = 'high';
    drawBackdrop(g, W, H);
    drawWater(g, W, H);
    drawNear(g);
    drawGuides(g, W);
    if (view.mode !== 'layers') drawOverlays(g);
  }

  // ---------------------------------------------------------------- 点中什么
  function pick(px, py) {
    const x = wx(px), y = wy(py), tol = 9 / view.zoom;
    const m = view.mode;
    if (m === 'pieces') {
      const items = val(planKey()).items.map((item, index) => ({item, index, box: boxOf(item)})).filter(e => e.box);
      items.sort((a, b) => b.item.z - a.item.z);
      const hit = items.find(e => x >= e.box.left && x <= e.box.right && y >= e.box.top && y <= e.box.bottom);
      return hit ? {kind: 'piece', index: hit.index} : null;
    }
    if (m === 'terrain') {
      const ramps = val(secKey('slopes'));
      for (let i = 0; i < ramps.length; i++) {
        const row = ramps[i], [a, ya, b, yb] = row;
        if (Math.hypot(x - a, y - ya) < tol * 1.4) return {kind: 'slope', index: i, handle: 'a'};
        if (Math.hypot(x - b, y - yb) < tol * 1.4) return {kind: 'slope', index: i, handle: 'b'};
        if (x > a && x < b && Math.abs(y - slopeY(row, x)) < tol) return {kind: 'slope', index: i, handle: null};
      }
      const edge = (row, low) => Math.abs(x - row[0]) < tol ? 'left' : Math.abs(x - row[1]) < tol ? 'right' : low !== null && low < STREET && Math.abs(y - low) < tol ? 'bottom' : low !== null && low < STREET && Math.abs(y - row[2]) < tol ? 'top' : null;
      // 线比块细，先看线
      for (const solid of [false, true]) for (const [kind, field] of [['platform', 'platforms'], ['block', 'blocks']]) {
        const rows = val(secKey(field));
        for (let i = 0; i < rows.length; i++) {
          const row = rows[i], low = lowOf(kind, row);
          if ((low !== null) !== solid || x <= row[0] - tol || x >= row[1] + tol) continue;
          if (low === null ? Math.abs(y - row[2]) < tol : y > row[2] - tol && y < low + tol) return {kind, index: i, handle: edge(row, low)};
        }
      }
    }
    if (m === 'spawns') { const i = val(secKey('spawns')).findIndex(([a, b]) => Math.hypot(a - x, b - 6 / view.zoom - y) < 14 / view.zoom); if (i >= 0) return {kind: 'spawn', index: i}; }
    if (m === 'lamps') {
      const i = val(secKey('lamps')).findIndex(([a, b, k, r]) => Math.hypot(a - x, (k === 'street' ? b - (r || 150) : b) - y) < 14 / view.zoom || (k === 'street' && Math.abs(a - x) < tol && y < b && y > b - (r || 150)));
      if (i >= 0) return {kind: 'lamp', index: i};
    }
    if (m === 'foreground') { const i = val(secKey('foreground')).findIndex(([a]) => Math.abs(a - x) < tol); if (i >= 0) return {kind: 'fg', index: i}; }
    return null;
  }

  // ---------------------------------------------------------------- 拖
  function snapPiece(item, x, disable) {
    if (disable) return x;
    const meta = metaOf(item), width = meta.attach[1] - meta.attach[0];
    let best = x, gap = 30;
    val(planKey()).items.forEach(other => {
      if (other === item) return;
      const b = boxOf(other);
      if (!b) return;
      for (const target of [b.attachR, b.attachL - width]) if (Math.abs(target - x) < gap) { gap = Math.abs(target - x); best = target; }
    });
    return best;
  }
  const snapFloor = (y, disable) => { if (disable) return y; const hit = FLOORS.find(([f]) => Math.abs(f - y) < 8); return hit ? hit[0] : y; };

  function startDrag(event) {
    canvas.setPointerCapture(event.pointerId);
    const rect = canvas.getBoundingClientRect(), px = event.clientX - rect.left, py = event.clientY - rect.top;
    // 中键、右键或按住空格：不管点到什么都是移动视图（楼铺满时没有空白处可拖）
    const panning = event.button !== 0 || spaceDown;
    const hit = view.mode === 'layers' || panning ? null : pick(px, py);
    if (hit) {
      selected = hit;
      live = {};
      const start = {px, py};
      if (hit.kind === 'piece') {
        const plan = clone(val(planKey())), item = plan.items[hit.index];
        const terrain = Object.fromEntries([...LINKED, 'spawns'].map(field => [field, clone(val(secKey(field)))]));
        drag = {type: 'piece', start, plan, item: clone(item), links: linksOf(item), terrain};
      } else {
        const field = FIELD_OF[hit.kind];
        drag = {type: 'row', start, field, rows: clone(val(secKey(field))), handle: hit.handle};
      }
      renderPanel();
    } else {
      if (!panning) selected = null;
      drag = {type: 'pan', px, py, x: view.x, y: view.y};
      renderPanel();
    }
    draw();
  }
  function moveDrag(event) {
    if (!drag) return;
    const rect = canvas.getBoundingClientRect(), px = event.clientX - rect.left, py = event.clientY - rect.top;
    if (drag.type === 'pan') {
      view.x = drag.x - (px - drag.px) / view.zoom;
      view.y = drag.y - (py - drag.py) / view.zoom;
      draw();
      return;
    }
    const dx = (px - drag.start.px) / view.zoom, dy = (py - drag.start.py) / view.zoom;
    if (Math.hypot(px - drag.start.px, py - drag.start.py) < 3 && !drag.moved) return;
    drag.moved = true;
    if (drag.type === 'piece') {
      const plan = clone(drag.plan), item = plan.items[selected.index], before = drag.item;
      const x = round(snapPiece(item, before.x + dx, event.altKey));
      let y = round(before.y + dy);
      if (!event.altKey && Math.abs(y) < 12) y = 0;
      item.x = x; item.y = y;
      live[planKey()] = withExtent(plan);
      Object.assign(live, movedLinks(drag.links, x - before.x, y - before.y, field => drag.terrain[field]));
    } else {
      const rows = clone(drag.rows), row = rows[selected.index];
      const from = drag.rows[selected.index], kind = selected.kind;
      if (kind === 'slope') {
        if (drag.handle === 'a') {
          const [ex, ey] = snapEnd(from[0] + dx, from[1] + dy, selected.index, event.altKey);
          row[0] = Math.min(round(ex), from[2] - 20); row[1] = round(ey);
        } else if (drag.handle === 'b') {
          const [ex, ey] = snapEnd(from[2] + dx, from[3] + dy, selected.index, event.altKey);
          row[2] = Math.max(round(ex), from[0] + 20); row[3] = round(ey);
        } else {
          shiftRow('slopes', row, dx, snapFloor(Math.max(from[1], from[3]) + dy, event.altKey) - Math.max(from[1], from[3]));
        }
      } else if (kind === 'platform' || kind === 'block') {
        const low = optOf(kind, from).bottom;
        if (drag.handle === 'left') row[0] = Math.min(round(from[0] + dx), from[1] - 20);
        else if (drag.handle === 'right') row[1] = Math.max(round(from[1] + dx), from[0] + 20);
        else if (drag.handle === 'bottom') setOpt(kind, row, 'bottom', Math.min(STREET, Math.max(round(low + dy), from[2] + 10)));
        else if (drag.handle === 'top') row[2] = Math.min(round(from[2] + dy), low - 10);
        else shiftRow(drag.field, row, dx, snapFloor(from[2] + dy, event.altKey) - from[2]);
      } else if (kind === 'fg') {
        row[0] = round(from[0] + dx);
      } else {
        row[0] = round(from[0] + dx);
        row[1] = round(kind === 'spawn' ? snapSurface(from[0] + dx, from[1] + dy, event.altKey) : from[1] + dy);
      }
      live[secKey(drag.field)] = rows;
    }
    draw();
    renderPanel();
  }
  // 出生点拖到平台附近就吸在台面上
  function snapSurface(x, y, disable) {
    if (disable) return y;
    const surfaces = standing().filter(([a, b]) => x >= a && x <= b).map(r => r[2]);
    for (const r of val(secKey('slopes'))) if (!isOff('slope', r) && x >= r[0] && x <= r[2]) surfaces.push(slopeY(r, x));
    surfaces.push(STREET);
    let best = y, gap = 24;
    for (const s of surfaces) if (Math.abs(s - y) < gap) { gap = Math.abs(s - y); best = s; }
    return best;
  }
  // 斜坡的端点：靠近别的平台端或斜坡端就接上，否则吸楼层线
  function snapEnd(x, y, self, disable) {
    if (disable) return [x, y];
    const points = [];
    for (const [a, b, s] of [...val(secKey('platforms')), ...val(secKey('blocks'))]) points.push([a, s], [b, s]);
    val(secKey('slopes')).forEach((r, i) => { if (i !== self) points.push([r[0], r[1]], [r[2], r[3]]); });
    let best = null, gap = 22;
    for (const p of points) { const d = Math.hypot(p[0] - x, p[1] - y); if (d < gap) { gap = d; best = p; } }
    return best ? [...best] : [x, snapFloor(y)];
  }
  // 还生效的平台和石台：[左, 右, 高度]
  const standing = () => [...val(secKey('platforms')).filter(r => !isOff('platform', r)), ...val(secKey('blocks')).filter(r => !isOff('block', r))].map(([a, b, y]) => [a, b, y]);
  function endDrag() {
    if (!drag) return;
    const pending = live, moved = drag.moved;
    drag = null;
    live = null;
    if (moved && pending && Object.keys(pending).length) save(pending);
    renderPanel();
    draw();
  }

  // ---------------------------------------------------------------- 操作
  function addPiece(id) {
    const piece = pieces()[id], plan = clone(val(planKey()));
    const free = plan.items.filter(i => i.z < 1000).map(i => i.z);
    const item = {piece: id, x: round(view.x - piece.w / 2 + piece.attach[0]), y: 0, z: (free.length ? Math.max(...free) : 0) + 1, mirror: false};
    plan.items.push(item);
    const own = terrainOf(item);
    selected = {kind: 'piece', index: plan.items.length - 1};
    save({[planKey()]: withExtent(plan), ...Object.fromEntries(LINKED.map(field => [secKey(field), [...val(secKey(field)), ...own[field]]]))});
    renderPanel(); draw();
  }
  function removeLinks(links, changes) {
    for (const field of LINKED) {
      const drop = new Set(links[field]);
      changes[secKey(field)] = (changes[secKey(field)] || val(secKey(field))).filter((_, i) => !drop.has(i));
    }
    return changes;
  }
  function removeSelected() {
    if (!selected) return;
    if (selected.kind === 'piece') {
      const plan = clone(val(planKey())), item = plan.items[selected.index];
      const changes = removeLinks(linksOf(item), {});
      plan.items.splice(selected.index, 1);
      changes[planKey()] = plan;
      save(changes);
    } else {
      const field = FIELD_OF[selected.kind];
      const rows = clone(val(secKey(field)));
      rows.splice(selected.index, 1);
      save({[secKey(field)]: rows});
    }
    selected = null;
    renderPanel(); draw();
  }
  function flipSelected() {
    const plan = clone(val(planKey())), item = plan.items[selected.index];
    const before = terrainOf(item), changes = removeLinks(linksOf(item), {});
    const hits = Object.fromEntries(LINKED.map(field => [field, matchRows(field, before[field])]));
    item.mirror = !item.mirror;
    const own = terrainOf(item);
    for (const field of LINKED) {
      // 删掉或单独挪开的那条不复活；关掉、改过挡不挡的翻过来还是那样
      const kept = own[field].flatMap((row, i) => {
        const hit = hits[field][i];
        if (hit < 0) return [];
        if (field !== 'lamps') { const old = val(secKey(field))[hit], at = optAt(KIND_OF[field]); if (old[at]) row[at] = clone(old[at]); row[at - 1] = old[at - 1]; }
        return [row];
      });
      changes[secKey(field)] = [...changes[secKey(field)], ...kept];
    }
    changes[planKey()] = plan;
    save(changes);
    renderPanel(); draw();
  }
  function setPieceField(field, value) {
    const plan = clone(val(planKey())), item = plan.items[selected.index], before = clone(item), links = linksOf(item);
    item[field] = value;
    const changes = {[planKey()]: withExtent(plan)};
    if (field === 'x' || field === 'y') Object.assign(changes, movedLinks(links, item.x - before.x, item.y - before.y));
    save(changes);
    draw();
  }
  function addRow(kind) {
    const x = round(view.x);
    const add = {
      platform: ['platforms', [x - 150, x + 150, 300, 'balcony']],
      block: ['blocks', [x - 120, x + 120, 470, 'steps']],
      slope: ['slopes', [x - 250, STREET, x + 250, STREET - 180, 'steps']],
      wall: ['blocks', [x - 20, x + 20, 300, 'stone']],
      spawn: ['spawns', [x, STREET]],
      lamp: ['lamps', [x, STREET, 'street', 326]],
      fg: ['foreground', [x, 'sign']],
    }[kind];
    const rows = [...val(secKey(add[0])), add[1]];
    selected = {kind: kind === 'wall' ? 'block' : kind, index: rows.length - 1};
    save({[secKey(add[0])]: rows});
    renderPanel(); draw();
  }
  function fit() {
    const plan = val(planKey());
    view.x = (plan.x0 + plan.x1) / 2;
    const top = Math.min(...plan.items.map(i => boxOf(i)?.top ?? 0));
    view.y = (top + BOTTOM) / 2;
    if (canvas && canvas.clientWidth) {
      view.zoom = Math.min((canvas.clientWidth - 40) / (plan.x1 - plan.x0), (canvas.clientHeight - 40) / (BOTTOM - top));
      // 画面比段矮的时候把河面贴到底边，空白留给天空
      view.y = BOTTOM + 12 / view.zoom - canvas.clientHeight / 2 / view.zoom;
    }
    view.fitted = true;
  }

  // ---------------------------------------------------------------- 校验
  function warnings() {
    const out = [];
    const surf = standing(), ramps = val(secKey('slopes')).filter(r => !isOff('slope', r));
    // 斜坡按一小段一小段算落脚点
    const pieceOf = r => { const list = [], n = Math.max(1, Math.ceil((r[2] - r[0]) / 100)); for (let i = 0; i < n; i++) { const a = r[0] + (r[2] - r[0]) * i / n, b = r[0] + (r[2] - r[0]) * (i + 1) / n; list.push([a, b, slopeY(r, (a + b) / 2), r]); } return list; };
    const steps = ramps.flatMap(pieceOf);
    const all = [...surf, ...steps, [-1e9, 1e9, STREET]];
    let tight = 0;
    for (const A of surf) for (const B of surf) if (A !== B && A[1] > B[0] && A[0] < B[1] && B[2] - A[2] > 0 && B[2] - A[2] < 188) tight++;
    if (tight) out.push(tight + ' 处平台上下太挤，站上去会顶头');
    const unreach = val(secKey('platforms')).filter(r => !isOff('platform', r)).filter(([a, b, y]) => !all.some(B => (B[2] > y && B[2] - y <= 300 && Math.max(0, Math.max(a, B[0]) - Math.min(b, B[1])) <= 380) || (Math.abs(B[2] - y) <= 60 && (B[0] !== a || B[1] !== b || B[2] !== y) && Math.max(0, Math.max(a, B[0]) - Math.min(b, B[1])) <= 450)));
    if (unreach.length) out.push(unreach.length + ' 个平台跳不上去');
    const steep = ramps.filter(r => Math.abs(r[3] - r[1]) >= r[2] - r[0]);
    if (steep.length) out.push(steep.length + ' 条斜坡太陡，走不上去（超过 45 度）');
    const cutoff = ramps.filter(r => { const low = r[1] > r[3] ? [r[0], r[1]] : [r[2], r[3]]; return low[1] < STREET - 1 && ![...surf, ...steps.filter(s => s[3] !== r), [-1e9, 1e9, STREET]].some(B => B[2] > low[1] - 60 && B[2] - low[1] <= 300 && Math.max(0, Math.max(low[0], B[0]) - Math.min(low[0], B[1])) <= 380); });
    if (cutoff.length) out.push(cutoff.length + ' 条斜坡下端够不着');
    const floating = val(secKey('spawns')).filter(([x, y]) => Math.abs(y - STREET) >= 1 && !surf.some(([a, b, s]) => x >= a && x <= b && Math.abs(s - y) < 1) && !ramps.some(r => x >= r[0] && x <= r[2] && Math.abs(slopeY(r, x) - y) < 4));
    if (floating.length) out.push(floating.length + ' 个出生点悬空');
    if (val(secKey('spawns')).length < 3) out.push('出生点太少，波次里的敌人会挤在一起');
    const far = image(texUrl(val('layout/backdrop/far/tex')));
    if (far && val('layout/backdrop/far/top') + far.naturalHeight * ART_SCALE < 0) out.push('远景图太矮，下面的雾会盖住天空');
    return out;
  }

  // ---------------------------------------------------------------- 右侧面板
  const num = (field, label, value, extra = '') => '<label class="sc-field"><span>' + esc(label) + '</span><input type="number" data-field="' + field + '" value="' + value + '" ' + extra + '></label>';
  const pieceName = id => String(id).replace(/^(s\d|b\d)_/, '').replace(/^导入_/, '');
  function panelPieces() {
    const plan = val(planKey());
    let html = '';
    if (selected?.kind === 'piece' && plan.items[selected.index]) {
      const item = plan.items[selected.index];
      html += '<section class="sc-card"><h3>' + esc(pieceName(item.piece)) + '</h3><div class="sc-grid">' + num('piece.x', '左右', item.x, 'step="1"') + num('piece.y', '上下', item.y, 'step="1"') + num('piece.z', '前后层', item.z, 'step="1"') + '</div><div class="sc-actions"><button data-act="flip">左右翻转</button><button data-act="delete" class="danger">删掉这一件</button></div><p class="sc-note">它带的平台、石台、斜坡和灯会跟着动，站在上面的出生点也会。</p></section>';
    } else {
      html += '<p class="sc-note">点楼选中，拖动摆放，靠近别的楼会吸住接缝（按住 Alt 不吸）。滚轮缩放，拖空白处移动视图。</p>';
    }
    html += '<section class="sc-card"><div class="sc-head"><h3>素材库</h3><label class="file-button">导入图片<input type="file" accept="image/*" data-import="piece" hidden></label></div><label class="sc-field sc-inline"><span>导入高度</span><input type="number" id="import-height" value="800" step="10" min="40"></label><div class="sc-shelf">' + scene().pieces.filter(p => p.id !== 'ledge').map(p => '<button class="sc-piece" data-add-piece="' + esc(p.id) + '" title="加到视图中间"><img src="' + esc(p.url) + '" alt="" loading="lazy"><span>' + esc(pieceName(p.id)) + '</span></button>').join('') + '</div></section>';
    return html;
  }
  const KIND_NAME = {platform: '平台', block: '石台', slope: '斜坡'};
  const MODE_HELP = {pass: '从下面能跳上来，按住下再跳能穿下去。', ground: '从顶面一直实心到地面，走路会被挡住。', part: '只实心到下沿：头顶和侧面都挡，下面够高的话能从下面走过去。'};
  function terrainCard(kind, row) {
    const mode = modeOf(kind, row), o = optOf(kind, row), si = kind === 'slope' ? 4 : 3;
    const coords = kind === 'slope'
      ? num('row.0', '左端', row[0]) + num('row.1', '左端高度', row[1]) + num('row.2', '右端', row[2]) + num('row.3', '右端高度', row[3])
      : num('row.0', '左端', row[0]) + num('row.1', '右端', row[1]) + num('row.2', '高度', row[2]) + (mode === 'part' ? num('opt.bottom', '下沿高度', o.bottom ?? row[2] + 16) : '');
    const modes = kind === 'slope' ? [['pass', '能跳穿'], ['ground', '实心到地面']] : [['pass', '能跳穿'], ['ground', '实心到地面'], ['part', '实心到某高度']];
    return '<section class="sc-card"><h3>' + KIND_NAME[kind] + '</h3><label class="sc-check"><input type="checkbox" data-opt="on"' + (o.off ? '' : ' checked') + '><span>有这个' + KIND_NAME[kind] + '</span></label><div class="sc-block-label">挡不挡</div><div class="seg sc-modes">' + modes.map(([id, name]) => '<button data-block="' + id + '" class="' + (id === mode ? 'active' : '') + '">' + name + '</button>').join('') + '</div><p class="sc-note">' + MODE_HELP[mode] + '</p><div class="sc-grid">' + coords + '</div><label class="sc-field"><span>样式</span><select data-field="row.' + si + '">' + [...new Set([row[si], ...STYLES])].map(s => '<option value="' + esc(s) + '"' + (s === row[si] ? ' selected' : '') + '>' + esc(STYLE_LABELS[s] || s) + '</option>').join('') + '</select></label><div class="sc-actions"><button data-act="delete" class="danger">删掉</button></div></section>';
  }
  function terrainList() {
    const list = [];
    for (const [kind, field] of [['platform', 'platforms'], ['block', 'blocks'], ['slope', 'slopes']]) val(secKey(field)).forEach((row, i) => list.push({kind, i, row, x: row[0]}));
    if (!list.length) return '';
    list.sort((a, b) => a.x - b.x);
    return '<section class="sc-card"><h3>这一段的地形</h3><div class="sc-list"><div class="sc-row sc-row-head"><span>从左到右</span><span>有</span><span>挡路</span></div>' + list.map(({kind, i, row}) => {
      const key = kind + '.' + i, off = isOff(kind, row), active = isSel(kind, i);
      const name = kind === 'slope' ? '斜坡 ' + Math.round(row[1]) + ' → ' + Math.round(row[3]) : KIND_NAME[kind] + ' 高 ' + Math.round(row[2]);
      return '<div class="sc-row' + (off ? ' is-off' : '') + (active ? ' active' : '') + '"><button data-pick="' + key + '">' + name + '</button><input type="checkbox" aria-label="' + name + ' 有没有" data-row-on="' + key + '"' + (off ? '' : ' checked') + '><input type="checkbox" aria-label="' + name + ' 挡不挡路" data-row-block="' + key + '"' + (modeOf(kind, row) === 'pass' ? '' : ' checked') + '></div>';
    }).join('') + '</div></section>';
  }
  function panelTerrain() {
    let html = '<div class="sc-actions"><button data-add="platform">加平台</button><button data-add="slope">加斜坡</button><button data-add="block">加石台</button><button data-add="wall">加墙</button></div>';
    const sel = selected, field = sel && KIND_OF[FIELD_OF[sel.kind]] ? FIELD_OF[sel.kind] : null, row = field && val(secKey(field))[sel.index];
    html += row ? terrainCard(sel.kind, row) : '<p class="sc-note">地形是看不见的碰撞，只决定能不能站、挡不挡，不改画面。金线能跳穿，紫块实心挡路，灰虚线是关掉的。拖两端改形状，拖中间移动。</p>';
    return html + terrainList();
  }
  function panelSimple(kind, field, title, hint, body) {
    let html = '<div class="sc-actions"><button data-add="' + kind + '">加' + title + '</button></div>';
    const row = selected?.kind === kind ? val(secKey(field))[selected.index] : null;
    html += row ? '<section class="sc-card"><h3>' + title + ' ' + (selected.index + 1) + '</h3>' + body(row) + '<div class="sc-actions"><button data-act="delete" class="danger">删掉</button></div></section>' : '<p class="sc-note">' + hint + '</p>';
    return html;
  }
  function texOptions(current) {
    const list = [...new Set([current, ...scene().images])];
    return list.map(t => '<option value="' + esc(t) + '"' + (t === current ? ' selected' : '') + '>' + esc(t.split('/').pop().replace(/\.png$/, '')) + '</option>').join('');
  }
  function panelLayers() {
    const depth = val('layout/backdrop/depth');
    const texRow = (key, title) => '<label class="sc-field"><span>' + title + '</span><select data-tex="' + key + '">' + texOptions(val(key)) + '</select></label>';
    return '<section class="sc-card"><div class="sc-head"><h3>图片</h3><label class="file-button">导入图片<input type="file" accept="image/*" data-import="layer" hidden></label></div>' + texRow('layout/backdrop/sky/tex', '天空') + texRow('layout/backdrop/far/tex', '远景') + '</section>' +
      '<section class="sc-card"><div class="sc-head"><h3>背街层（先画远的）</h3><button data-act="add-depth">加一层</button></div>' + depth.map((row, i) => '<div class="sc-depth"><label class="sc-field"><span>图片</span><select data-depth="' + i + '.tex">' + texOptions(row.tex) + '</select></label><div class="sc-grid"><label class="sc-field"><span>跟镜头</span><input type="number" step="0.01" min="0" max="1.5" data-depth="' + i + '.scroll" value="' + row.scroll + '"></label><label class="sc-field"><span>下沿高度</span><input type="number" step="5" data-depth="' + i + '.bottom" value="' + row.bottom + '"></label><button data-del-depth="' + i + '" class="sc-del" aria-label="删掉这一层">×</button></div></div>').join('') + '</section>' +
      ctx.sectionsHtml(page);
  }
  function panel() {
    switch (view.mode) {
      case 'pieces': return panelPieces();
      case 'terrain': return panelTerrain();
      case 'spawns': return panelSimple('spawn', 'spawns', '出生点', '波次里的敌人按这里的顺序左右交替出生。拖动三角摆放，靠近台面会吸住。', row => '<div class="sc-grid">' + num('row.0', '左右', row[0]) + num('row.1', '脚底高度', row[1]) + '</div>');
      case 'lamps': return panelSimple('lamp', 'lamps', '灯', '灯决定角色和雨被照亮的地方。成图里的灯杆是画死的，这里移动的是光。', row => '<div class="sc-grid">' + num('row.0', '左右', row[0]) + num('row.1', '高度', row[1]) + (row[2] === 'street' ? num('row.3', '灯头离地', row[3] ?? 150) : '') + '</div><label class="sc-field"><span>类型</span><select data-field="row.2"><option value="street"' + (row[2] === 'street' ? ' selected' : '') + '>路灯</option><option value="wall"' + (row[2] === 'wall' ? ' selected' : '') + '>壁灯</option></select></label>');
      case 'foreground': return panelSimple('fg', 'foreground', '前景', '前景挡在角色前面，比镜头移动得快，压到角色时会变淡。', row => num('row.0', '左右', row[0]) + '<label class="sc-field"><span>类型</span><select data-field="row.1">' + FG_KINDS.map(([v, l]) => '<option value="' + v + '"' + (row[1] === v ? ' selected' : '') + '>' + l + '</option>').join('') + '</select></label>');
      default: return panelLayers();
    }
  }
  function renderPanel() {
    const el = root?.querySelector('.sc-panel');
    if (!el) return;
    // 正在输入时不重画，免得丢焦点
    if (el.contains(document.activeElement) && document.activeElement.matches('input,select') && !drag) { renderWarnings(); return; }
    const top = el.scrollTop;
    el.innerHTML = panel();
    el.scrollTop = top;
    renderWarnings();
  }
  function renderWarnings() {
    const el = root?.querySelector('.sc-warnings');
    if (!el) return;
    const list = warnings();
    el.textContent = list.join('；');
    el.hidden = !list.length;
  }
  function renderBar() {
    root.querySelector('.sc-bar').innerHTML = '<div class="seg">' + names().map((n, i) => '<button data-section="' + i + '" class="' + (i === view.section ? 'active' : '') + '">' + esc(n) + '</button>').join('') + '</div><div class="seg">' + MODES.map(([id, l]) => '<button data-mode="' + id + '" class="' + (id === view.mode ? 'active' : '') + '">' + l + '</button>').join('') + '</div><span class="sc-spacer"></span><span class="sc-bake" hidden>正在出预览…</span><span class="sc-warnings" hidden></span><button data-act="fit">看全段</button>';
  }

  // ---------------------------------------------------------------- 事件
  async function importImage(input) {
    const file = input.files[0], kind = input.dataset.import;
    if (!file) return;
    try {
      const bitmap = await createImageBitmap(file);
      const k = kind === 'piece' ? Math.min(1, Number(root.querySelector('#import-height')?.value || 800) * scene().px / bitmap.height) : 1;
      const out = document.createElement('canvas');
      out.width = Math.max(1, Math.round(bitmap.width * k));
      out.height = Math.max(1, Math.round(bitmap.height * k));
      const g = out.getContext('2d');
      g.imageSmoothingQuality = 'high';
      g.drawImage(bitmap, 0, 0, out.width, out.height);
      const result = await ctx.api('/api/scene/import', 'POST', {kind, name: file.name, data: out.toDataURL('image/png')});
      if (kind === 'piece') { scene().pieces.push(result.piece); ctx.notify('已加进素材库。'); addPiece(result.piece.id); }
      else { scene().images.push(result.tex); ctx.notify('图片已导入，在下拉框里选用。'); renderPanel(); }
    } catch (error) { ctx.notify(error.message, true); }
    input.value = '';
  }
  function onClick(event) {
    const t = event.target.closest('button');
    if (!t) return;
    if (t.dataset.section) { view.section = Number(t.dataset.section); selected = null; fit(); renderBar(); renderPanel(); draw(); queuePreview(0); return; }
    if (t.dataset.mode) { view.mode = t.dataset.mode; selected = null; renderBar(); renderPanel(); draw(); return; }
    if (t.dataset.addPiece) { addPiece(t.dataset.addPiece); return; }
    if (t.dataset.add) { addRow(t.dataset.add); return; }
    if (t.dataset.pick) {
      const [kind, index] = t.dataset.pick.split('.'), row = val(secKey(FIELD_OF[kind]))[index];
      selected = {kind, index: Number(index)};
      const a = row[0], b = kind === 'slope' ? row[2] : row[1];
      if (sx(b) < 0 || sx(a) > canvas.clientWidth) view.x = (a + b) / 2;
      renderPanel(); draw();
      return;
    }
    if (t.dataset.block) { editRow(selected.kind, selected.index, row => setMode(selected.kind, row, t.dataset.block)); return; }
    if (t.dataset.delDepth) { const rows = clone(val('layout/backdrop/depth')); rows.splice(Number(t.dataset.delDepth), 1); save({'layout/backdrop/depth': rows}); renderPanel(); draw(); return; }
    const act = t.dataset.act;
    if (act === 'fit') { fit(); draw(); }
    if (act === 'flip') flipSelected();
    if (act === 'delete') removeSelected();
    if (act === 'add-depth') { const rows = clone(val('layout/backdrop/depth')); rows.push({tex: scene().images[0], scroll: 0.6, bottom: 540}); save({'layout/backdrop/depth': rows}); renderPanel(); draw(); }
  }
  function editRow(kind, index, change) {
    const field = FIELD_OF[kind], rows = clone(val(secKey(field)));
    change(rows[index]);
    save({[secKey(field)]: rows});
    document.activeElement?.blur?.();
    renderPanel(); draw();
  }
  function onChange(event) {
    const t = event.target;
    if (t.dataset.import) { importImage(t); return; }
    if (t.dataset.opt === 'on') { editRow(selected.kind, selected.index, row => setOpt(selected.kind, row, 'off', t.checked ? undefined : true)); return; }
    if (t.dataset.rowOn) { const [kind, i] = t.dataset.rowOn.split('.'); editRow(kind, Number(i), row => setOpt(kind, row, 'off', t.checked ? undefined : true)); return; }
    if (t.dataset.rowBlock) { const [kind, i] = t.dataset.rowBlock.split('.'); editRow(kind, Number(i), row => setMode(kind, row, !t.checked ? 'pass' : kind === 'platform' ? 'part' : 'ground')); return; }
    if (t.dataset.tex) { save({[t.dataset.tex]: t.value}); draw(); return; }
    if (t.dataset.depth) {
      const [i, field] = t.dataset.depth.split('.'), rows = clone(val('layout/backdrop/depth'));
      rows[i][field] = field === 'tex' ? t.value : Number(t.value);
      save({'layout/backdrop/depth': rows}); draw();
      return;
    }
    const field = t.dataset.field;
    if (!field) return;
    const [scope, key] = field.split('.');
    if (scope === 'piece') {
      if (!Number.isFinite(Number(t.value)) || t.value.trim() === '') { renderPanel(); return; }
      setPieceField(key, Number(t.value));
      return;
    }
    const name = FIELD_OF[selected.kind];
    const rows = clone(val(secKey(name))), row = rows[selected.index];
    if (scope === 'opt') {
      if (Number(t.value) <= row[2]) { ctx.notify('下沿要比高度的数大（数越大越低）。', true); t.blur(); renderPanel(); return; }
      setOpt(selected.kind, row, key, Number(t.value));
    } else row[key] = t.tagName === 'SELECT' ? t.value : Number(t.value);
    if ((name === 'platforms' || name === 'blocks') && row[0] >= row[1]) { ctx.notify('左端要比右端小。', true); t.blur(); renderPanel(); return; }
    if (name === 'slopes' && row[0] >= row[2]) { ctx.notify('左端要比右端小。', true); t.blur(); renderPanel(); return; }
    if ((name === 'platforms' || name === 'blocks') && optOf(selected.kind, row).bottom !== undefined && optOf(selected.kind, row).bottom <= row[2]) setOpt(selected.kind, row, 'bottom', Math.min(row[2] + 16, STREET));
    save({[secKey(name)]: rows});
    t.blur();
    renderPanel(); draw();
  }
  function onKey(event) {
    if (event.code === 'Space') { spaceDown = event.type === 'keydown' && !!root?.isConnected && !event.target.matches?.('input,select,textarea,button'); if (spaceDown) event.preventDefault(); return; }
    if (event.type !== 'keydown' || !root?.isConnected || event.target.matches?.('input,select,textarea') || !selected) return;
    if (event.key === 'Delete' || event.key === 'Backspace') { event.preventDefault(); removeSelected(); return; }
    const step = event.shiftKey ? 10 : 1, move = {ArrowLeft: [-step, 0], ArrowRight: [step, 0], ArrowUp: [0, -step], ArrowDown: [0, step]}[event.key];
    if (!move) return;
    event.preventDefault();
    if (selected.kind === 'piece') {
      const item = val(planKey()).items[selected.index];
      setPieceField('x', round(item.x + move[0]));
      if (move[1]) setPieceField('y', round(val(planKey()).items[selected.index].y + move[1]));
    } else {
      const name = FIELD_OF[selected.kind];
      const rows = clone(val(secKey(name)));
      shiftRow(name, rows[selected.index], move[0], move[1]);
      save({[secKey(name)]: rows});
    }
    renderPanel(); draw();
  }
  function onWheel(event) {
    event.preventDefault();
    const rect = canvas.getBoundingClientRect(), px = event.clientX - rect.left, py = event.clientY - rect.top;
    const x = wx(px), y = wy(py);
    view.zoom = Math.max(0.04, Math.min(1.5, view.zoom * (event.deltaY < 0 ? 1.15 : 1 / 1.15)));
    view.x = x - (px - canvas.clientWidth / 2) / view.zoom;
    view.y = y - (py - canvas.clientHeight / 2) / view.zoom;
    draw();
  }
  document.addEventListener('keydown', onKey);
  document.addEventListener('keyup', onKey);

  // ---------------------------------------------------------------- 对 app.js 的接口
  function init(context) { ctx = context; }
  function mount(el, catalogPage) {
    page = catalogPage;
    root = el;
    root.innerHTML = '<div class="sc-bar"></div><div class="sc-main"><div class="sc-stage"><canvas></canvas></div><aside class="sc-panel"></aside></div>';
    canvas = root.querySelector('canvas');
    if (!scene()) { root.textContent = '找不到雨街素材库。'; return; }
    renderBar();
    root.addEventListener('click', onClick);
    root.addEventListener('change', onChange);
    canvas.addEventListener('pointerdown', startDrag);
    canvas.addEventListener('pointermove', moveDrag);
    canvas.addEventListener('pointerup', endDrag);
    canvas.addEventListener('pointercancel', endDrag);
    canvas.addEventListener('wheel', onWheel, {passive: false});
    canvas.addEventListener('contextmenu', event => event.preventDefault());
    canvas.addEventListener('dblclick', event => {
      if (view.mode !== 'terrain') return;
      const rect = canvas.getBoundingClientRect();
      if (pick(event.clientX - rect.left, event.clientY - rect.top)) return;
      const x = round(wx(event.clientX - rect.left)), y = round(snapFloor(wy(event.clientY - rect.top)));
      const rows = [...val(secKey('platforms')), [x - 150, x + 150, y, 'balcony']];
      selected = {kind: 'platform', index: rows.length - 1};
      save({[secKey('platforms')]: rows});
      renderPanel(); draw();
    });
    observer?.disconnect();
    observer = new ResizeObserver(() => { if (!view.fitted) fit(); draw(); });
    observer.observe(root.querySelector('.sc-stage'));
    renderPanel();
    if (canvas.clientWidth && !view.fitted) fit();
    draw();
    queuePreview(0);
  }
  function refresh() { if (root?.isConnected) { draw(); renderWarnings(); queuePreview(); } }
  // 搜索跳到远层和雨的参数时，那些行在“远层和雨”模式的面板里
  function reveal() { view.mode = 'layers'; selected = null; }

  // 应用前：改过楼的段先出图，成图路径写进改动里；没改楼的段用默认成图。
  async function prepareApply() {
    if (!ctx.state.scene) return;
    const list = names();
    const next = clone(ctx.values);
    let dirty = false;
    for (let i = 0; i < list.length; i++) {
      const artKey = 'layout/sections/' + list[i] + '/art', plan = next['scene/plan/' + i];
      if (!plan) {
        if (Object.hasOwn(next, artKey)) { delete next[artKey]; dirty = true; }
        continue;
      }
      ctx.notify('正在给' + list[i] + '出图…');
      const {art} = await ctx.api('/api/scene/bake', 'POST', {plan});
      if (!equal(next[artKey], art)) { next[artKey] = art; dirty = true; }
    }
    if (dirty) ctx.commit(next, false);
  }

  const GROUPS = [['楼', i => ['scene/plan/' + i, secKey('art', i)]], ['地形', i => [secKey('platforms', i), secKey('blocks', i), secKey('slopes', i)]], ['出生点', i => [secKey('spawns', i)]], ['灯', i => [secKey('lamps', i)]], ['前景', i => [secKey('foreground', i)]]];
  function groups() {
    if (!ctx.state.scene) return [];
    const out = [];
    names().forEach((name, i) => GROUPS.forEach(([label, keys]) => out.push({label: name + '：' + label, keys: keys(i)})));
    out.push({label: '远层图片', keys: ['layout/backdrop/sky/tex', 'layout/backdrop/far/tex', 'layout/backdrop/depth']});
    return out;
  }
  function changesHtml(applied) {
    const rows = groups().filter(g => g.keys.some(k => Object.hasOwn(ctx.values, k) || Object.hasOwn(applied, k)));
    if (!rows.length) return '';
    return '<div class="change-group"><h3>雨街布局</h3>' + rows.map(g => {
      const pending = g.keys.some(k => !equal(ctx.values[k], applied[k]));
      return '<div class="change-row"><button class="change-jump" data-page="scene">' + esc(g.label) + '<span class="change-badge ' + (pending ? 'staged' : '') + '">' + (pending ? '还没应用' : '已在游戏里') + '</span></button><button class="change-remove" data-scene-reset="' + esc(g.keys.join('|')) + '" aria-label="恢复默认">×</button></div>';
    }).join('') + '</div>';
  }
  function pendingCount(applied) { return groups().filter(g => g.keys.some(k => !equal(ctx.values[k], applied[k]))).length; }

  return {init, mount, refresh, reveal, prepareApply, changesHtml, pendingCount};
})();
