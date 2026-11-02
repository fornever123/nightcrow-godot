// UI 会话 10-31：左上血条 / 大招三个方向的动态样图（用户：“不好看，你先给我方案看看样子”）。
// 坐标都是游戏 1280x720 的像素；同一条时间线 sim(t) 驱动三个方向，方便对比。
// ?mode=sheet&dir=N 画单个方向的四态静态表；?mode=video 把三个方向逐帧导出到 #out（Edge --dump-dom 取走）。
const P = new URLSearchParams(location.search);
const MODE = P.get('mode') || 'sheet', DIR = +(P.get('dir') || 1);
const C = {INK:'#07090e', MOON:'#e6e9ef', SILVER:'#aab2c0', BONE:'#e9e4d8', STEEL:'#6d778a', MIST:'#8f99ab',
  VIOLET:'#9a6cff', VL:'#c8b0ff', WINE:'#a3283a', WINED:'#5e1420', BLOOD:'#e06a7c'};
const K = 0.445;
const HITS = [[5.5, 70], [6.5, 40], [7.5, 18]];
const T_U0 = 1.5, T_UF = 4.0, T_REL = 9.3, T_END = 10.6;
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
const ease = x => 1 - Math.pow(1 - clamp(x, 0, 1), 3);
const lerp = (a, b, k) => a + (b - a) * k;
function rng(seed) { let s = (seed * 7919) % 2147483647 || 1; return () => { s = (s * 16807) % 2147483647; return s / 2147483647; }; }
function hex(c) { return [1, 3, 5].map(i => parseInt(c.substr(i, 2), 16)); }
function mix(a, b, k) { const A = hex(a), B = hex(b); return 'rgb(' + A.map((v, i) => Math.round(lerp(v, B[i], clamp(k, 0, 1)))).join(',') + ')'; }
function rgba(c, a) { return 'rgba(' + hex(c).join(',') + ',' + clamp(a, 0, 1) + ')'; }

function sim(t) {
  let hp = 100, lag = 100, last = -99, prev = 100, idx = -1;
  const evolve = (lag, hp, t0, t1) => Math.max(hp, lag - 110 * Math.max(0, t1 - t0 - 0.4));
  for (let i = 0; i < HITS.length; i++) {
    const [ht, v] = HITS[i];
    if (t < ht) break;
    lag = evolve(lag, hp, last, ht); prev = hp; hp = v; last = ht; idx = i;
  }
  lag = evolve(lag, hp, last, t);
  const ult = t < T_U0 ? 0 : t < T_UF ? (t - T_U0) / (T_UF - T_U0) : t < T_REL ? 1 : 0;
  return {t, hp, lag, prev, hitAge: t - last, ult, full: t >= T_UF && t < T_REL, fullAge: t - T_UF, relAge: t - T_REL,
    low: hp < 30, hb: hp < 30 ? Math.pow(Math.max(0, Math.sin(t * 6.2)), 8) : 0, sheen: ((t + 1.2) % 3.0) / 0.7};
}

// ---------- 小工具 ----------
function para(ctx, x, y, w, h, k = K) {
  ctx.beginPath(); ctx.moveTo(x + h * k, y); ctx.lineTo(x + w + h * k, y); ctx.lineTo(x + w, y + h); ctx.lineTo(x, y + h); ctx.closePath();
}
function line(ctx, x1, y1, x2, y2, color, w = 1) { ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2); ctx.strokeStyle = color; ctx.lineWidth = w; ctx.stroke(); }
function fadeLine(ctx, x1, y1, x2, y2, color, a, w = 1) {
  const g = ctx.createLinearGradient(x1, y1, x2, y2); g.addColorStop(0, rgba(color, a)); g.addColorStop(1, rgba(color, 0));
  line(ctx, x1, y1, x2, y2, g, w);
}
function say(ctx, s, x, y, font, color, align = 'left', spacing = 0, alpha = 1) {
  ctx.save(); ctx.globalAlpha *= alpha; ctx.font = font; ctx.textAlign = align; ctx.letterSpacing = spacing + 'px';
  ctx.fillStyle = 'rgba(0,0,0,.75)'; ctx.fillText(s, x + 1, y + 2); ctx.fillStyle = color; ctx.fillText(s, x, y); ctx.restore();
}
function diamond(ctx, x, y, r, color) { ctx.beginPath(); ctx.moveTo(x, y - r); ctx.lineTo(x + r, y); ctx.lineTo(x, y + r); ctx.lineTo(x - r, y); ctx.closePath(); ctx.fillStyle = color; ctx.fill(); }
function jolt(s, amp = 7) { return s.hitAge < 0.3 ? Math.sin(s.hitAge * 95) * amp * (1 - s.hitAge / 0.3) : 0; }
function wave(ctx) { say(ctx, '第 1 轮 · 封印 1/3 · 第 1/2 波', 30, 134, '13px "Noto Serif SC"', C.MIST, 'left', 3); }

// 血条：斜切槽 + 酒红残影 + 白色本体 + 十格刻痕 + 寒光 + 受击白闪 + 崩出的碎片
function hpBar(ctx, s, x, y, w, h, k = K, cuts = 10) {
  para(ctx, x, y, w, h, k); ctx.fillStyle = 'rgba(7,9,14,.86)'; ctx.fill();
  ctx.strokeStyle = s.low ? rgba(C.WINE, 0.45 + 0.5 * s.hb) : 'rgba(109,119,138,.75)'; ctx.lineWidth = 1; ctx.stroke();
  if (s.lag > s.hp + 0.1) { para(ctx, x, y, w * s.lag / 100, h, k); ctx.fillStyle = s.hitAge < 0.07 ? '#fff' : C.WINE; ctx.fill(); }
  const fw = w * s.hp / 100;
  para(ctx, x, y, fw, h, k);
  const g = ctx.createLinearGradient(0, y, 0, y + h);
  if (s.low) { g.addColorStop(0, mix(C.BLOOD, '#ffffff', 0.35 * s.hb)); g.addColorStop(1, C.WINED); }
  else { g.addColorStop(0, '#ffffff'); g.addColorStop(0.55, '#e3e7ee'); g.addColorStop(1, '#a9b1bf'); }
  ctx.fillStyle = g; ctx.fill();
  ctx.save(); para(ctx, x, y, fw, h, k); ctx.clip();
  if (cuts) for (let i = 1; i < cuts; i++) { const sx = x + w * i / cuts; line(ctx, sx + h * k, y, sx, y + h, 'rgba(7,9,14,.45)', 1.5); }
  if (s.sheen < 1) {
    const bx = x - 50 + (w + 100) * ease(s.sheen), sg = ctx.createLinearGradient(bx, 0, bx + 30 + h * k, 0);
    sg.addColorStop(0, 'rgba(255,255,255,0)'); sg.addColorStop(0.5, 'rgba(255,255,255,.85)'); sg.addColorStop(1, 'rgba(255,255,255,0)');
    para(ctx, bx, y, 30, h, k); ctx.fillStyle = sg; ctx.fill();
  }
  if (s.hitAge < 0.12) { ctx.fillStyle = 'rgba(255,255,255,' + (1 - s.hitAge / 0.12) + ')'; ctx.fillRect(x - 5, y - 2, w + 40, h + 4); }
  ctx.restore();
  ctx.save(); ctx.shadowColor = s.low ? C.BLOOD : '#ffffff'; ctx.shadowBlur = 8;
  line(ctx, x + fw + h * k + 1, y - 3, x + fw - 3 * k + 1, y + h + 3, '#ffffff', 2); ctx.restore();
  shards(ctx, s, x, y, w, h, k);
}
function shards(ctx, s, x, y, w, h, k) {
  for (let i = 0; i < HITS.length; i++) {
    const a = s.t - HITS[i][0];
    if (a < 0 || a > 0.8) continue;
    const from = i ? HITS[i - 1][1] : 100, to = HITS[i][1], r = rng(i + 3);
    for (let j = 0; j < 9; j++) {
      const f = lerp(to, from, (j + r()) / 9) / 100, px = x + w * f + h * k * 0.5, py = y + h * r();
      const vx = 50 + r() * 230, vy = -60 - r() * 200, sz = 4 + r() * 10, spin = (r() - 0.5) * 18;
      ctx.save(); ctx.translate(px + vx * a, py + vy * a + 300 * a * a); ctx.rotate(spin * a);
      ctx.globalAlpha = 1 - a / 0.8; para(ctx, -sz / 2, -sz * 0.35, sz, sz * 0.7, 0.5);
      ctx.fillStyle = a < 0.1 ? '#fff' : (j % 3 ? C.WINE : C.BONE); ctx.fill(); ctx.restore();
    }
  }
}
// 数字：受击放大回弹 + 酒红闪；旧数字被“斩开”——上半往左、下半往右滑走
function hpNumber(ctx, s, x, y, size, align, sliced) {
  const font = 'italic 700 ' + size + 'px Georgia';
  let color = C.BONE;
  if (s.hitAge < 0.25) color = mix('#ff8f9e', C.BONE, s.hitAge / 0.25);
  else if (s.low) color = mix(C.BONE, C.BLOOD, 0.35 + 0.55 * s.hb);
  if (s.hitAge < 0.4) {
    const a = 1 - s.hitAge / 0.4, d = ease(s.hitAge / 0.4) * size * 1.6;
    for (const [top, dx] of [[true, -d], [false, d]]) {
      ctx.save(); ctx.beginPath();
      if (sliced) { if (top) ctx.rect(x - 300, y - size * 1.2, 600, size * 0.83); else ctx.rect(x - 300, y - size * 0.37, 600, size); }
      else if (!top) ctx.rect(0, 0, 0, 0); else ctx.rect(x - 300, y - size * 1.2, 600, size * 2);
      ctx.clip(); say(ctx, String(s.prev), x + (sliced ? dx : d * 0.5), y - (sliced ? 0 : d * 0.15), font, C.BLOOD, align, 0, a * 0.85); ctx.restore();
    }
    if (sliced && s.hitAge < 0.14) {
      const k2 = 1 - s.hitAge / 0.14; ctx.save(); ctx.shadowColor = '#fff'; ctx.shadowBlur = 12;
      line(ctx, x - size * 0.4, y - size * 0.18, x + size * 2.3, y - size * 0.62, 'rgba(255,255,255,' + k2 + ')', 3 * k2 + 0.5); ctx.restore();
    }
  }
  const sc = (s.hitAge < 0.18 ? 1.28 - 0.28 * ease(s.hitAge / 0.18) : 1) * (1 + 0.05 * s.hb);
  ctx.save(); ctx.translate(x, y - size * 0.35); ctx.scale(sc, sc); say(ctx, String(s.hp), 0, size * 0.35, font, color, align); ctx.restore();
}
function readyText(ctx, s, x, y, big = 18) {
  if (!s.full) return;
  const k2 = ease(s.fullAge / 0.28);
  ctx.save(); ctx.beginPath(); ctx.rect(x - 6, y - 40, 150 * k2, 60); ctx.clip();
  ctx.shadowColor = C.VIOLET; ctx.shadowBlur = 10 + 6 * Math.sin(s.t * 5);
  say(ctx, '绝影', x, y, '900 ' + big + 'px "Source Han Serif SC Heavy"', C.VL, 'left', 4);
  say(ctx, 'J + K', x + big * 2 + 18, y - 1, 'italic 13px Georgia', C.MOON, 'left', 1);
  ctx.restore();
  if (k2 < 1) { ctx.save(); ctx.shadowColor = C.VL; ctx.shadowBlur = 10; line(ctx, x - 6 + 150 * k2 + 8, y - 26, x - 6 + 150 * k2 - 4, y + 8, '#fff', 2); ctx.restore(); }
}
function burst(ctx, s, pts, spread) {   // 放大招：紫色碎片从 pts 飞散
  if (s.relAge < 0 || s.relAge > 0.75) return;
  const a = s.relAge, r = rng(41);
  pts.forEach(([px, py, dx, dy], i) => {
    const sp = 120 + r() * spread, vx = dx * sp + r() * 60, vy = dy * sp - r() * 80, sz = 3 + r() * 7;
    ctx.save(); ctx.translate(px + vx * a, py + vy * a); ctx.rotate(r() * 6 + a * 8); ctx.globalAlpha = 1 - a / 0.75;
    ctx.shadowColor = C.VIOLET; ctx.shadowBlur = 8; para(ctx, -sz, -sz * 0.3, sz * 2, sz * 0.6, 0.6);
    ctx.fillStyle = i % 3 ? C.VIOLET : C.VL; ctx.fill(); ctx.restore();
  });
}

// ---------- 方向一 · 斜刃：斜切黑底板，数字牌 + 粗血条 + 下面一条紫色大招刃 ----------
function d1(ctx, s) {
  ctx.save(); ctx.translate(jolt(s), 0);
  ctx.beginPath(); ctx.moveTo(0, 14); ctx.lineTo(560, 14); ctx.lineTo(520, 104); ctx.lineTo(0, 104); ctx.closePath();
  let g = ctx.createLinearGradient(0, 0, 560, 0);
  g.addColorStop(0, 'rgba(7,9,14,.88)'); g.addColorStop(0.55, 'rgba(7,9,14,.7)'); g.addColorStop(1, 'rgba(7,9,14,0)');
  ctx.fillStyle = g; ctx.fill();
  fadeLine(ctx, 0, 14.5, 540, 14.5, C.MOON, 0.6); fadeLine(ctx, 0, 103.5, 480, 103.5, C.STEEL, 0.5);
  if (s.low) { g = ctx.createRadialGradient(40, 58, 4, 40, 58, 120); g.addColorStop(0, rgba(C.WINE, 0.2 + 0.6 * s.hb)); g.addColorStop(1, rgba(C.WINE, 0)); ctx.fillStyle = g; ctx.fillRect(0, 15, 200, 88); }
  para(ctx, 14, 28, 100, 58); ctx.fillStyle = 'rgba(4,5,9,.95)'; ctx.fill();
  ctx.strokeStyle = s.low ? rgba(C.BLOOD, 0.4 + 0.6 * s.hb) : 'rgba(170,178,192,.5)'; ctx.lineWidth = 1; ctx.stroke();
  ctx.beginPath(); ctx.moveTo(14 + 58 * K, 28); ctx.lineTo(14 + 58 * K + 16, 28); ctx.lineTo(14 + 58 * K - 3.5, 36); ctx.closePath(); ctx.fillStyle = C.VIOLET; ctx.fill();
  hpNumber(ctx, s, 82, 72, 40, 'center', false);
  hpBar(ctx, s, 146, 33, 340, 20);
  // 大招刃
  const x = 128, y = 62, w = 340, h = 8;
  para(ctx, x, y, w, h); ctx.fillStyle = 'rgba(7,9,14,.86)'; ctx.fill(); ctx.strokeStyle = 'rgba(154,108,255,.35)'; ctx.stroke();
  const u = s.full ? 1 : s.ult, rel = s.relAge >= 0 && s.relAge < 0.15;
  if (u > 0 || rel) {
    const fw = w * (rel ? 1 : u); ctx.save();
    ctx.globalAlpha = rel ? 1 - s.relAge / 0.15 : 1;
    if (s.full) { ctx.shadowColor = C.VIOLET; ctx.shadowBlur = 12 + 6 * Math.sin(s.t * 5); }
    para(ctx, x, y, fw, h); g = ctx.createLinearGradient(x, 0, x + fw, 0);
    g.addColorStop(0, rgba(C.VIOLET, 0.55)); g.addColorStop(1, s.full ? '#e6dcff' : C.VL); ctx.fillStyle = rel ? '#fff' : g; ctx.fill(); ctx.restore();
    ctx.save(); para(ctx, x, y, fw, h); ctx.clip();
    if (s.full) for (let i = 0; i < 3; i++) { const sx = x - 30 + ((s.fullAge * 320 + i * 140) % (w + 60)); para(ctx, sx, y, 20, h); ctx.fillStyle = 'rgba(255,255,255,.75)'; ctx.fill(); }
    ctx.restore();
    if (!s.full && !rel) { ctx.save(); ctx.shadowColor = C.VL; ctx.shadowBlur = 8; line(ctx, x + fw + h * K, y - 2, x + fw - 1, y + h + 2, '#f0e8ff', 2); ctx.restore(); }
  }
  for (const f of [1 / 3, 2 / 3]) line(ctx, x + w * f + h * K, y - 3, x + w * f, y + h + 3, 'rgba(200,176,255,.6)', 1);
  if (s.full && s.fullAge < 0.35) { const k2 = s.fullAge / 0.35; ctx.save(); ctx.globalAlpha = 1 - k2; ctx.translate(x + w / 2, y + h / 2); ctx.scale(1 + 0.12 * k2, 1 + 2.5 * k2); para(ctx, -w / 2, -h / 2, w, h); ctx.fillStyle = '#fff'; ctx.fill(); ctx.restore(); }
  readyText(ctx, s, 482, 74);
  const pts = []; for (let i = 0; i < 26; i++) pts.push([x + w * i / 25, y + 4, 0.8, -0.5]); burst(ctx, s, pts, 420);
  ctx.restore(); wave(ctx);
}

// ---------- 方向二 · 鸦眼：左边一圈鸦眼徽记，外环就是大招，满了眼睛睁开；右边细长血条 ----------
function d2(ctx, s) {
  const cx = 62, cy = 60;
  ctx.save(); ctx.translate(jolt(s, 5), 0);
  let g = ctx.createLinearGradient(80, 0, 560, 0);
  g.addColorStop(0, 'rgba(7,9,14,.8)'); g.addColorStop(0.6, 'rgba(7,9,14,.55)'); g.addColorStop(1, 'rgba(7,9,14,0)');
  ctx.beginPath(); ctx.moveTo(70, 34); ctx.lineTo(560, 34); ctx.lineTo(540, 90); ctx.lineTo(70, 90); ctx.closePath(); ctx.fillStyle = g; ctx.fill();
  g = ctx.createRadialGradient(cx, cy, 20, cx, cy, 64); g.addColorStop(0, 'rgba(4,5,9,.95)'); g.addColorStop(0.7, 'rgba(4,5,9,.85)'); g.addColorStop(1, 'rgba(4,5,9,0)');
  ctx.fillStyle = g; ctx.fillRect(cx - 70, cy - 70, 140, 140);
  // 血条与上下两道细轨
  fadeLine(ctx, 104, 43.5, 500, 43.5, C.SILVER, 0.65); diamond(ctx, 104, 43.5, 3, C.SILVER);
  fadeLine(ctx, 104, 79.5, 400, 79.5, C.STEEL, 0.55);
  hpBar(ctx, s, 108, 52, 360, 14, K, 0);
  for (let i = 1; i < 4; i++) { const sx = 108 + 360 * i / 4; line(ctx, sx + 14 * K, 46, sx + 14 * K - 1.5, 50, C.SILVER, 1); }
  hpNumber(ctx, s, 488, 67, 26, 'left', false);
  // 环
  const rot = s.full ? s.fullAge * 0.35 : 0;
  ctx.save(); ctx.translate(cx, cy);
  if (s.hitAge < 0.45) { const k2 = s.hitAge / 0.45; ctx.beginPath(); ctx.arc(0, 0, 44 + 30 * ease(k2), 0, Math.PI * 2); ctx.strokeStyle = rgba(C.BLOOD, 0.8 * (1 - k2)); ctx.lineWidth = 2; ctx.stroke(); }
  ctx.beginPath(); ctx.arc(0, 0, 31, 0, Math.PI * 2); ctx.strokeStyle = 'rgba(170,178,192,.55)'; ctx.lineWidth = 1; ctx.stroke();
  ctx.beginPath(); ctx.arc(0, 0, 45, 0, Math.PI * 2); ctx.strokeStyle = s.low ? rgba(C.BLOOD, 0.35 + 0.6 * s.hb) : 'rgba(109,119,138,.5)'; ctx.stroke();
  for (let i = 0; i < 36; i++) {
    const a = rot + i * Math.PI / 18, big = i % 9 === 0, r1 = 45, r2 = big ? 53 : 48;
    line(ctx, Math.cos(a) * r1, Math.sin(a) * r1, Math.cos(a) * r2, Math.sin(a) * r2, big ? C.SILVER : 'rgba(143,153,171,.55)', big ? 1.5 : 1);
  }
  ctx.beginPath(); ctx.arc(0, 0, 38, 0, Math.PI * 2); ctx.strokeStyle = 'rgba(154,108,255,.14)'; ctx.lineWidth = 6; ctx.stroke();
  const u = s.full ? 1 : s.ult;
  if (u > 0) {
    ctx.save(); ctx.shadowColor = C.VIOLET; ctx.shadowBlur = s.full ? 14 + 6 * Math.sin(s.t * 5) : 6;
    ctx.beginPath(); ctx.arc(0, 0, 38, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * u); ctx.strokeStyle = s.full ? C.VL : C.VIOLET; ctx.lineWidth = 6; ctx.stroke();
    if (!s.full) { const a = -Math.PI / 2 + Math.PI * 2 * u; diamond(ctx, Math.cos(a) * 38, Math.sin(a) * 38, 4.5, '#f0e8ff'); }
    ctx.restore();
  }
  for (let i = 0; i < 3; i++) { const a = -Math.PI / 2 + i * Math.PI * 2 / 3; line(ctx, Math.cos(a) * 34, Math.sin(a) * 34, Math.cos(a) * 42, Math.sin(a) * 42, C.INK, 2); }
  if (s.full && s.fullAge < 0.4) { const k2 = s.fullAge / 0.4; ctx.beginPath(); ctx.arc(0, 0, 38 + 26 * ease(k2), 0, Math.PI * 2); ctx.strokeStyle = 'rgba(230,220,255,' + (1 - k2) + ')'; ctx.lineWidth = 3; ctx.stroke(); }
  // 眼
  let o = 0;
  if (s.full) { o = ease(s.fullAge / 0.35); const b = (s.fullAge - 0.9) % 3.2; if (b > 0 && b < 0.16) o *= Math.abs(b - 0.08) / 0.08; }
  if (s.hitAge < 0.22) o *= 0.35;
  if (o > 0.05) {
    ctx.save(); ctx.shadowColor = C.VIOLET; ctx.shadowBlur = 18;
    ctx.beginPath(); ctx.moveTo(-24, 0); ctx.quadraticCurveTo(0, -26 * o, 24, 0); ctx.quadraticCurveTo(0, 22 * o, -24, 0); ctx.closePath();
    ctx.fillStyle = '#05060a'; ctx.fill(); ctx.strokeStyle = C.MOON; ctx.lineWidth = 1.5; ctx.stroke(); ctx.restore();
    ctx.save(); ctx.beginPath(); ctx.moveTo(-24, 0); ctx.quadraticCurveTo(0, -26 * o, 24, 0); ctx.quadraticCurveTo(0, 22 * o, -24, 0); ctx.clip();
    g = ctx.createRadialGradient(0, 0, 1, 0, 0, 10); g.addColorStop(0, '#f2ecff'); g.addColorStop(0.45, C.VL); g.addColorStop(1, C.VIOLET);
    ctx.beginPath(); ctx.arc(0, 0, 10, 0, Math.PI * 2); ctx.fillStyle = g; ctx.fill();
    ctx.beginPath(); ctx.ellipse(0, 0, 2, 9 * o, 0, 0, Math.PI * 2); ctx.fillStyle = '#05060a'; ctx.fill();
    ctx.beginPath(); ctx.arc(3.5, -3.5, 1.6, 0, Math.PI * 2); ctx.fillStyle = '#fff'; ctx.fill(); ctx.restore();
  } else {
    ctx.beginPath(); ctx.moveTo(-22, -1); ctx.quadraticCurveTo(0, 9, 22, -1); ctx.strokeStyle = C.SILVER; ctx.lineWidth = 1.6; ctx.stroke();
    if (u > 0) { ctx.save(); ctx.globalAlpha = 0.25 + 0.75 * u; ctx.shadowColor = C.VIOLET; ctx.shadowBlur = 10; ctx.beginPath(); ctx.moveTo(-12 * u, 4); ctx.quadraticCurveTo(0, 6.5, 12 * u, 4); ctx.strokeStyle = C.VL; ctx.lineWidth = 1.5; ctx.stroke(); ctx.restore(); }
  }
  const pts = []; for (let i = 0; i < 30; i++) { const a = i * Math.PI / 15; pts.push([Math.cos(a) * 38, Math.sin(a) * 38, Math.cos(a), Math.sin(a)]); }
  burst(ctx, s, pts, 160);
  ctx.restore();
  readyText(ctx, s, 112, 104, 16);
  ctx.restore(); wave(ctx);
}

// ---------- 方向三 · 爪痕：大号斜体血量数字主导，右边三道爪痕就是三段大招 ----------
function claw(ctx, x) {
  ctx.beginPath(); ctx.moveTo(x + 36, 20); ctx.quadraticCurveTo(x + 26, 56, x, 94); ctx.quadraticCurveTo(x + 12, 58, x + 36, 20); ctx.closePath();
}
function clawW(ctx, x) {
  ctx.beginPath(); ctx.moveTo(x + 36, 20); ctx.quadraticCurveTo(x + 30, 60, x, 94); ctx.quadraticCurveTo(x + 10, 54, x + 36, 20); ctx.closePath();
}
function d3(ctx, s) {
  ctx.save(); ctx.translate(jolt(s, 6), 0);
  let g = ctx.createRadialGradient(120, 60, 10, 140, 60, 260); g.addColorStop(0, 'rgba(5,6,10,.85)'); g.addColorStop(0.6, 'rgba(5,6,10,.5)'); g.addColorStop(1, 'rgba(5,6,10,0)');
  ctx.fillStyle = g; ctx.fillRect(0, 0, 520, 150);
  if (s.low) { g = ctx.createRadialGradient(70, 66, 5, 70, 66, 110); g.addColorStop(0, rgba(C.WINE, 0.15 + 0.45 * s.hb)); g.addColorStop(1, rgba(C.WINE, 0)); ctx.fillStyle = g; ctx.fillRect(0, 0, 220, 150); }
  hpNumber(ctx, s, 24, 86, 64, 'left', true);
  hpBar(ctx, s, 24, 97, 250, 5, 0.6, 4);
  const xs = [176, 208, 240];
  for (let i = 0; i < 3; i++) {
    const x = xs[i], f = s.full ? 1 : clamp(s.ult * 3 - i, 0, 1), done = T_U0 + (T_UF - T_U0) * (i + 1) / 3, age = s.t - done;
    const flyA = s.relAge >= 0 ? s.relAge : -1;
    ctx.save();
    if (flyA >= 0) { if (flyA > 0.5) { ctx.restore(); continue; } ctx.translate(flyA * (900 + i * 200), -flyA * 160); ctx.globalAlpha = 1 - flyA / 0.5; ctx.transform(1 + flyA * 3, 0, 0, 1, 0, 0); }
    if (s.full) for (const [dx, a] of [[14, 0.12], [7, 0.25]]) { ctx.save(); ctx.translate(dx + Math.sin(s.t * 9 + i) * 1.5, -dx * 0.4); claw(ctx, x); ctx.fillStyle = rgba(C.VIOLET, a); ctx.fill(); ctx.restore(); }
    clawW(ctx, x); ctx.fillStyle = 'rgba(4,5,9,.9)'; ctx.fill(); ctx.strokeStyle = 'rgba(143,153,171,.7)'; ctx.lineWidth = 1; ctx.stroke();
    if (f > 0) {
      ctx.save(); clawW(ctx, x); ctx.clip(); g = ctx.createLinearGradient(0, 94, 0, 20);
      g.addColorStop(0, C.VIOLET); g.addColorStop(1, s.full ? '#efe8ff' : C.VL);
      if (s.full) { ctx.shadowColor = C.VIOLET; ctx.shadowBlur = 14; }
      ctx.fillStyle = g; ctx.fillRect(x - 4, 94 - 76 * f, 44, 76 * f);
      if (f < 1) line(ctx, x - 4, 94 - 76 * f, x + 44, 94 - 76 * f, '#f6f0ff', 2);
      ctx.restore();
    }
    if (age >= 0 && age < 0.3) {
      const k2 = age / 0.3; ctx.save(); ctx.globalAlpha = 1 - k2; clawW(ctx, x); ctx.fillStyle = '#fff'; ctx.fill();
      ctx.shadowColor = C.VL; ctx.shadowBlur = 10; const e = 18 + 30 * ease(k2);
      line(ctx, x + 36 + e * 0.38, 20 - e, x - e * 0.38, 94 + e, 'rgba(240,232,255,.9)', 2 * (1 - k2) + 0.5); ctx.restore();
    }
    ctx.restore();
  }
  readyText(ctx, s, 292, 60, 22);
  ctx.restore(); wave(ctx);
}

const DRAW = {1: d1, 2: d2, 3: d3};
const NAMES = {1: '方向一 · 斜刃', 2: '方向二 · 鸦眼', 3: '方向三 · 爪痕'};
const CROP = {w: 600, h: 150};

function crop(ctx, bg, d, t, ox, oy, sc) {
  ctx.save(); ctx.translate(ox, oy); ctx.scale(sc, sc);
  ctx.beginPath(); ctx.rect(0, 0, CROP.w, CROP.h); ctx.clip();
  ctx.drawImage(bg, 0, 0, CROP.w, CROP.h, 0, 0, CROP.w, CROP.h);
  DRAW[d](ctx, sim(t)); ctx.restore();
}

function stage(t) {
  const L = ['寒光扫过', '大招充能', '大招满', '受击', '低血心跳', '放出大招'];
  if (t < T_U0) return L[0]; if (t < T_UF) return L[1]; if (t < HITS[0][0]) return L[2];
  if (t < HITS[2][0]) return L[3]; if (t < T_REL) return L[4]; return L[5];
}

function main(bg) {
  const cv = document.getElementById('c'), ctx = cv.getContext('2d');
  if (MODE === 'sheet') {
    const sc = 1.5, W = CROP.w * sc, H = CROP.h * sc, states = [[2.6, '常态（大招充到一半，血条寒光扫过）'], [4.7, '大招满（发光 + “绝影 J+K”滑出）'], [6.6, '受击瞬间（白闪、崩碎片、数字被打出去）'], [8.45, '低血（酒红心跳）']];
    cv.width = W * 2 + 30; cv.height = H * 2 + 150;
    ctx.fillStyle = '#05060a'; ctx.fillRect(0, 0, cv.width, cv.height);
    say(ctx, NAMES[DIR], 24, 50, '900 30px "Source Han Serif SC Heavy"', C.MOON, 'left', 6);
    states.forEach(([t, label], i) => {
      const ox = 10 + (i % 2) * (W + 10), oy = 80 + Math.floor(i / 2) * (H + 34);
      crop(ctx, bg, DIR, t, ox, oy, sc);
      say(ctx, label, ox + 6, oy + H + 24, '15px "Noto Serif SC"', C.SILVER, 'left', 1);
    });
  } else if (MODE === 'full') {
    cv.width = 1280; cv.height = 720; ctx.drawImage(bg, 0, 0, 1280, 720); DRAW[DIR](ctx, sim(+(P.get('t') || 4.7)));
  } else {
    const sc = 1.6, W = CROP.w * sc, H = CROP.h * sc, out = [];
    cv.width = W; cv.height = H * 3 + 44;
    for (let f = 0; f * (1 / 30) < T_END; f++) {
      const t = f / 30;
      ctx.fillStyle = '#05060a'; ctx.fillRect(0, 0, cv.width, cv.height);
      for (let d = 1; d <= 3; d++) {
        crop(ctx, bg, d, t, 0, (d - 1) * H, sc);
        say(ctx, NAMES[d], W - 14, (d - 1) * H + 26, '900 15px "Source Han Serif SC Heavy"', C.MOON, 'right', 3, 0.85);
        if (d < 3) line(ctx, 0, d * H - 0.5, W, d * H - 0.5, '#000', 2);
      }
      say(ctx, stage(t), 20, H * 3 + 30, '700 17px "Noto Serif SC"', C.VL, 'left', 4);
      ctx.fillStyle = C.STEEL; ctx.fillRect(220, H * 3 + 22, (W - 250), 2);
      ctx.fillStyle = C.MOON; ctx.fillRect(220, H * 3 + 22, (W - 250) * t / T_END, 2);
      out.push(cv.toDataURL('image/jpeg', 0.9));
    }
    document.getElementById('out').textContent = out.join('\n');
  }
}
const img = new Image(); img.onload = () => main(img); img.src = BG64;
