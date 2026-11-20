'use strict';
// 场景：读素材库和拼接方案、出图、导入图片。雨街默认数据（布局、方案、素材库）都只读，改动存在 tuning.json。
const fs = require('node:fs/promises');
const path = require('node:path');
const crypto = require('node:crypto');
const {spawn} = require('node:child_process');
const {normalizePlan} = require('./model');

const KIT_DIR = 'docs/视觉设计/雨夜河岸街/素材库';
const ART_DIR = 'assets/image/rain_street';
const PIECES_DIR = 'tools/modifier/scene/pieces';
const BAKED_DIR = 'tools/modifier/scene/baked';
const IMAGE_ROOTS = [KIT_DIR, ART_DIR, PIECES_DIR];
const PYTHONS = [['py', ['-3.10']], ['python', []]];

const readJson = async file => JSON.parse((await fs.readFile(file, 'utf8')).replace(/^﻿/, ''));
const exists = file => fs.access(file).then(() => true, () => false);
const bad = message => Object.assign(Error(message), {status: 400});

function sceneManager(root) {
  const at = rel => path.join(root, rel);
  const piecesFile = at('tools/modifier/scene/pieces.json');

  async function kit() {
    const base = await readJson(at(KIT_DIR + '/kit.json'));
    const extra = await exists(piecesFile) ? (await readJson(piecesFile)).pieces : {};
    return {px: base.px_per_world, street: base.street, pieces: {...base.pieces, ...extra}, extra};
  }

  async function images() {
    const out = [];
    for (const dir of [ART_DIR, ART_DIR + '/edits']) {
      const names = await fs.readdir(at(dir)).catch(() => []);
      for (const name of names) if (/\.png$/i.test(name) && !/^near_/.test(name)) out.push('res://' + dir + '/' + name);
    }
    return out;
  }

  // 给 createModel 的文档：没有这些文件（比如测试沙盒）就当没有场景。
  async function documents() {
    const layoutFile = at('assets/data/rain_street_layout.json');
    if (!await exists(layoutFile) || !await exists(at(KIT_DIR + '/kit.json'))) return null;
    const layout = await readJson(layoutFile), planFile = await readJson(at('tools/art/rain_street_compose.json')), k = await kit();
    const plan = {};
    for (const section of planFile.sections) plan[section.index] = normalizePlan(section, k.pieces);
    return {layout, scene: {plan}};
  }

  async function info() {
    const k = await kit().catch(() => null);
    if (!k) return null;
    const pieces = Object.values(k.pieces).map(p => ({...p, url: imageUrl(k.extra[p.id] ? PIECES_DIR + '/' + p.file : KIT_DIR + '/' + p.file), imported: !!k.extra[p.id]}));
    const layout = await readJson(at('assets/data/rain_street_layout.json')).catch(() => ({}));
    return {px: k.px, pieces, images: await images(), arenaHalf: layout.arenaHalf ?? 2400, spacing: layout.arenaSpacing ?? 6400};
  }

  const imageUrl = rel => '/scene-image?path=' + encodeURIComponent(rel);

  async function readImage(rel) {
    const clean = path.posix.normalize(String(rel).replace(/\\/g, '/'));
    if (clean.startsWith('..') || !IMAGE_ROOTS.some(dir => clean.startsWith(dir + '/')) || !/\.png$/i.test(clean)) throw Object.assign(Error('不允许读取这个文件'), {status: 403});
    return fs.readFile(at(clean));
  }

  function runPython(job) {
    const attempt = index => new Promise((resolve, reject) => {
      const [cmd, args] = PYTHONS[index];
      const child = spawn(cmd, [...args, path.join(root, 'tools/modifier/bake_scene.py')], {cwd: root, windowsHide: true, env: {...process.env, PYTHONIOENCODING: 'utf-8'}});
      let out = '', err = '';
      child.stdout.on('data', d => { out += d; });
      child.stderr.on('data', d => { err += d; });
      child.on('error', e => reject(e));
      child.on('close', code => {
        if (code !== 0) return reject(Object.assign(Error(err.trim().split('\n').pop() || '出图失败'), {detail: err}));
        const last = out.trim().split('\n').pop();
        try { resolve(JSON.parse(last).art); } catch { reject(Error('出图没有返回结果')); }
      });
      child.stdin.end(JSON.stringify(job));
    }).catch(e => {
      if (index + 1 < PYTHONS.length && (e.code === 'ENOENT' || /cv2/.test(e.detail || ''))) return attempt(index + 1);
      throw Object.assign(e, {status: 500});
    });
    return attempt(0);
  }

  // 同一份方案只出一次图：文件名带方案的哈希。
  async function bake(plan) {
    const k = await kit();
    for (const item of plan.items || []) if (!k.pieces[item.piece]) throw bad('素材库里没有这一件：' + item.piece);
    const hash = crypto.createHash('sha256').update(JSON.stringify([plan, k.extra])).digest('hex').slice(0, 12);
    const out = 'edits/near_' + plan.index + '_' + hash + '.png', record = at(BAKED_DIR + '/' + hash + '.json');
    if (await exists(record) && await exists(at(ART_DIR + '/' + out))) return readJson(record);
    const extra = {};
    for (const [id, piece] of Object.entries(k.extra)) extra[id] = {...piece, file: at(PIECES_DIR + '/' + piece.file)};
    const art = await runPython({plan, out, extra});
    await fs.mkdir(path.dirname(record), {recursive: true});
    await fs.writeFile(record, JSON.stringify(art));
    return art;
  }

  // 反复调楼会留下很多成图。应用后删掉 tuning.json 和方案都不再用的（撤销回去时会按方案重新出图）。
  async function prune(presetsDir) {
    const dir = at(ART_DIR + '/edits');
    const texts = [await fs.readFile(at('assets/data/tuning.json'), 'utf8').catch(() => '')];
    for (const name of await fs.readdir(presetsDir).catch(() => [])) texts.push(await fs.readFile(path.join(presetsDir, name), 'utf8').catch(() => ''));
    const used = texts.join(' ');
    for (const name of await fs.readdir(dir).catch(() => [])) {
      const png = name.replace(/\.import$/, '');
      if (/^near_.*\.png$/.test(png) && !used.includes(png)) await fs.rm(path.join(dir, name), {force: true});
    }
  }

  function pngSize(buffer) {
    if (buffer.length < 24 || buffer.toString('latin1', 1, 4) !== 'PNG') throw bad('只支持 PNG 图片');
    return {width: buffer.readUInt32BE(16), height: buffer.readUInt32BE(20)};
  }

  const safeName = name => String(name || '').replace(/\.[a-z0-9]+$/i, '').replace(/[^\p{L}\p{N}_-]+/gu, '_').slice(0, 40) || 'image';

  async function importImage(input) {
    const buffer = Buffer.from(String(input.data || '').replace(/^data:[^,]*,/, ''), 'base64');
    const size = pngSize(buffer), name = safeName(input.name), tag = crypto.createHash('sha256').update(buffer).digest('hex').slice(0, 6);
    if (input.kind === 'layer') {
      const rel = ART_DIR + '/edits/layer_' + name + '_' + tag + '.png';
      await fs.mkdir(path.dirname(at(rel)), {recursive: true});
      await fs.writeFile(at(rel), buffer);
      return {tex: 'res://' + rel, ...size};
    }
    if (input.kind !== 'piece') throw bad('不认识的导入类型');
    const k = await kit(), id = '导入_' + name + '_' + tag, file = id + '.png';
    const w = Math.round(size.width / k.px * 10) / 10, h = Math.round(size.height / k.px * 10) / 10;
    const piece = {name: id, id, file, w, top: Math.round((k.street - 4 - h) * 10) / 10, h, attach: [0, w], scale: 1, relight: false, seam: false, unique: false, tags: ['imported'], stand: [], blocks: [], lamps: [], source: 'modifier import'};
    await fs.mkdir(at(PIECES_DIR), {recursive: true});
    await fs.writeFile(at(PIECES_DIR + '/' + file), buffer);
    await fs.writeFile(piecesFile, JSON.stringify({pieces: {...k.extra, [id]: piece}}, null, 2) + '\n');
    return {piece: {...piece, url: imageUrl(PIECES_DIR + '/' + file), imported: true}};
  }

  return {documents, info, readImage, bake, importImage, prune};
}

module.exports = {sceneManager};
