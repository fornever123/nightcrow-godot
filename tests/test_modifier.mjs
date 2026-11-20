import assert from 'node:assert/strict';
import { promises as fs } from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import net from 'node:net';
import { spawn, execFile } from 'node:child_process';
import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const node = process.platform === 'win32' ? 'E:/node.exe' : process.execPath;
const runFile = promisify(execFile);
const hash = data => createHash('sha256').update(data).digest('hex');
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const protectedPaths = ['assets/data/battle.json', 'assets/data/encounters.json', 'assets/data/tuning.json'];
async function snapshot(base, names) {
  const result = {};
  for (const name of names) {
    try { result[name] = hash(await fs.readFile(path.join(base, name))); }
    catch (error) { if (error.code !== 'ENOENT') throw error; result[name] = null; }
  }
  return result;
}
const original = await snapshot(root, protectedPaths);
const sandbox = await fs.mkdtemp(path.join(os.tmpdir(), 'nightcrow-modifier-test-'));
let server;
let serverOutput = '';
let base;
let passed = 0;
let failed = 0;
let skipped = 0;
let state;
let model;
let lib;
let battle;
let encounters;
let catalog;
const fakePids = new Set();
async function check(name, callback) {
  try { await callback(); passed++; console.log('PASS ' + name); }
  catch (error) {
    if (error.code === 'TEST_SKIP') { skipped++; console.log('SKIP ' + name + '：' + error.message); }
    else { failed++; console.error('FAIL ' + name + '\n' + (error.stack || error)); }
  }
}
async function api(route, method = 'GET', body, expected = 200) {
  const response = await fetch(base + route, {
    method, headers: body === undefined ? {} : {'Content-Type': 'application/json'},
    body: body === undefined ? undefined : typeof body === 'string' ? body : JSON.stringify(body),
    signal: AbortSignal.timeout(10000),
  });
  const text = await response.text();
  assert.equal(response.status, expected, method + ' ' + route + ': ' + text);
  return text ? JSON.parse(text) : {};
}
function resolvePath(docs, text) {
  return text.split('/').reduce((value, key) => Array.isArray(value)
    ? value.find(entry => entry.id === key) : value?.[key], docs);
}
function sorted(value) {
  if (Array.isArray(value)) return value.map(sorted);
  if (value && typeof value === 'object') return Object.fromEntries(Object.keys(value).sort().map(key => [key, sorted(value[key])]));
  return value;
}
function alive(pid) {
  try { process.kill(pid, 0); return true; } catch { return false; }
}
async function waitFor(callback, label, milliseconds = 10000) {
  const end = Date.now() + milliseconds;
  while (Date.now() < end) { if (await callback()) return; await sleep(80); }
  throw new Error('等待超时：' + label);
}
async function killTree(pid) {
  if (!pid || !alive(pid)) return;
  if (process.platform === 'win32') {
    try { await runFile('taskkill', ['/PID', String(pid), '/T', '/F'], {windowsHide: true}); } catch {}
  }
  if (alive(pid)) { try { process.kill(pid, 'SIGTERM'); } catch {} }
  await waitFor(() => !alive(pid), '清理自有进程 ' + pid, 5000);
}

try {
  catalog = JSON.parse(await fs.readFile(path.join(root, 'tools/modifier/catalog.json'), 'utf8'));
  encounters = JSON.parse(await fs.readFile(path.join(root, 'assets/data/encounters.json'), 'utf8'));
  battle = JSON.parse(await fs.readFile(path.join(root, 'assets/data/battle.json'), 'utf8'));
  await fs.mkdir(path.join(sandbox, 'assets/data'), {recursive: true});
  await fs.mkdir(path.join(sandbox, 'tools/modifier'), {recursive: true});
  for (const name of ['battle.json', 'encounters.json']) await fs.copyFile(path.join(root, 'assets/data', name), path.join(sandbox, 'assets/data', name));
  await fs.copyFile(path.join(root, 'tools/modifier/catalog.json'), path.join(sandbox, 'tools/modifier/catalog.json'));
  const defaultsBefore = await snapshot(sandbox, protectedPaths.slice(0, 2));
  const fakeScript = path.join(sandbox, 'fake-godot.js');
  await fs.writeFile(fakeScript, "const fs = require('node:fs');\nconst {spawn} = require('node:child_process');\nconst child = spawn(process.execPath, ['-e','setInterval(()=>{},1000)'], {stdio:'ignore',windowsHide:true});\nfs.appendFileSync(" + JSON.stringify(path.join(sandbox, 'fake-launches.jsonl')) + ", JSON.stringify({pid:process.pid,childPid:child.pid,args:process.argv.slice(2)})+'\\n');\nsetInterval(()=>{},1000);\n");
  const fakeGodot = fakeScript;
  const probe = net.createServer();
  await new Promise((resolve, reject) => { probe.once('error', reject); probe.listen(0, '127.0.0.1', resolve); });
  const port = probe.address().port;
  await new Promise(resolve => probe.close(resolve));
  base = 'http://127.0.0.1:' + port;
  server = spawn(node, [path.join(root, 'tools/modifier/server.js'), '--root', sandbox, '--port', String(port), '--godot', fakeGodot], {
    cwd: root, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'],
  });
  server.stdout.on('data', chunk => { serverOutput += chunk; });
  server.stderr.on('data', chunk => { serverOutput += chunk; });
  server.on('error', error => { serverOutput += error.stack; });
  await waitFor(async () => {
    if (server.exitCode !== null) throw new Error('服务启动退出：' + serverOutput);
    try { const response = await fetch(base + '/api/state', {signal: AbortSignal.timeout(500)}); return response.ok; } catch { return false; }
  }, '沙盒服务启动');
  const require = createRequire(import.meta.url);
  lib = require(path.join(root, 'tools/modifier/lib/model.js'));
  model = lib.createModel(catalog, {battle, encounters});

  await check('清单全部 path/key 解析默认值，only/exclude/section.only 生效', () => {
    const expectedPaths = new Set();
    for (const page of catalog.pages) for (const section of page.sections || []) {
      const entities = page.template === 'moves' ? page.moves : page.template === 'enemies' ? page.kinds : [{id: ''}];
      for (const entity of entities) for (const item of section.items) {
        if (section.only && !section.only.includes(entity.id) || section.exclude?.includes(entity.id)
          || item.only && !item.only.includes(entity.id) || item.exclude?.includes(entity.id)
          || item.excludeBurst && entity.burst) continue;
        if (item.phase) continue;
        const itemPath = item.path || (page.template === 'moves' ? 'battle/moves/' : 'encounters/kinds/') + entity.id + '/' + item.key;
        const value = resolvePath({battle, encounters}, itemPath);
        assert.ok(value !== undefined || Object.hasOwn(item, 'default'), '清单缺少默认值：' + itemPath);
        expectedPaths.add(itemPath);
        const expanded = model.items.find(candidate => candidate.path === itemPath);
        assert.ok(expanded, '未展开：' + itemPath);
        assert.deepEqual(expanded.defaultValue, value === undefined ? item.default : value, itemPath);
      }
    }
    for (const item of model.items.filter(item => !item.phase)) {
      assert.ok(expectedPaths.has(item.path) || item.path === 'encounters/waves', '不应显示：' + item.path);
    }
  });

  await check('GET state 只返回参数和紧凑时间数据，不发送完整动画', async () => {
    state = await api('/api/state');
    assert.equal(path.resolve(state.projectRoot), path.resolve(sandbox));
    assert.deepEqual(state.values, {});
    assert.ok(state.revision);
    assert.ok(Array.isArray(state.items) && state.items.length > 100);
    assert.ok(Array.isArray(state.moves));
    assert.equal(state.moves.length, battle.moves.length);
    assert.ok(!JSON.stringify(state).includes('"animations":'), 'state 泄漏完整动画');
    const again = await api('/api/state');
    assert.equal(again.revision, state.revision, '无文件 revision 必须固定');
    await assert.rejects(fs.access(path.join(sandbox, 'assets/data/tuning.json')));
  });

  await check('apply 原子写排序/LF/2空格 tuning，默认文件字节不变', async () => {
    const values = {'encounters/kinds/grunt/hp': 100, 'battle/moves/light_1/damage': 12, 'battle/characters/player/speed': 800};
    const applied = await api('/api/apply', 'POST', {values, baseRevision: state.revision});
    const bytes = await fs.readFile(path.join(sandbox, 'assets/data/tuning.json'), 'utf8');
    assert.equal(bytes, JSON.stringify(sorted({version: 1, values}), null, 2) + '\n');
    assert.ok(!bytes.includes('\r'));
    assert.equal(applied.revision, hash(bytes));
    state = await api('/api/state');
    assert.deepEqual(state.values, values);
    const speedItem = state.items.find(item => item.path === 'battle/characters/player/speed');
    assert.equal(speedItem.currentValue, 800);
    assert.equal(speedItem.currentDisplayValue, 800);
    assert.equal(speedItem.defaultDisplayValue, 680);
    assert.deepEqual(await snapshot(sandbox, protectedPaths.slice(0, 2)), defaultsBefore);
    assert.deepEqual((await fs.readdir(path.join(sandbox, 'assets/data'))).sort(), ['battle.json', 'encounters.json', 'tuning.json']);
  });

  await check('拒绝未知路径、原型路径、非有限数字和错误 bool；范围外数字允许', async () => {
    for (const values of [
      {'battle/unknown/value': 1}, {'battle/characters/player/sprite/animations/attack_1/fps': 12},
      {'battle/__proto__/polluted': 1}, {'battle/characters/player/speed': null},
      {'encounters/kinds/grunt/armor': 1}, {'battle/characters/player/speed': 'fast'},
      {'battle/characters/player/speed': true},
    ]) await api('/api/apply', 'POST', {values, baseRevision: state.revision}, 400);
    for (const raw of ['1e999', '-1e999', 'NaN', 'Infinity']) {
      await api('/api/apply', 'POST', '{"values":{"battle/characters/player/speed":' + raw + '},"baseRevision":' + JSON.stringify(state.revision) + '}', 400);
    }
    const outside = {'battle/characters/player/speed': 100000};
    await api('/api/apply', 'POST', {values: outside, baseRevision: state.revision});
    state = await api('/api/state');
    assert.deepEqual(state.values, outside);
  });

  await check('波次合法保存、空 spawns/非法 kind/非正整数拒绝', async () => {
    const valid = structuredClone(encounters.waves);
    valid[0][0].label = '沙盒测试';
    await api('/api/apply', 'POST', {values: {'encounters/waves': valid}, baseRevision: state.revision});
    state = await api('/api/state');
    assert.deepEqual(state.values['encounters/waves'], valid);
    const invalid = [null, {}, [null], [[null]]];
    for (const patch of [
      {spawns: []}, {spawns: ['missing']}, {spawns: [0]}, {reinforce: ['missing']},
      {reinforce_at: 0}, {reinforce_at: -1}, {reinforce_at: 1.2}, {reinforce_at: '2'},
      {max_attackers: 0}, {max_attackers: 1.2}, {max_attackers: false},
    ]) { const waves = structuredClone(valid); Object.assign(waves[0][0], patch); invalid.push(waves); }
    for (const waves of invalid) await api('/api/apply', 'POST', {values: {'encounters/waves': waves}, baseRevision: state.revision}, 400);
  });

  await check('外部内容 revision 冲突返回409且不覆盖外部文件', async () => {
    const tuningPath = path.join(sandbox, 'assets/data/tuning.json');
    const external = '{"version":1,"values":{"battle/characters/player/speed":777}}\n';
    await fs.writeFile(tuningPath, external);
    await api('/api/apply', 'POST', {values: {}, baseRevision: state.revision}, 409);
    assert.equal(await fs.readFile(tuningPath, 'utf8'), external);
    state = await api('/api/state');
    assert.equal(state.revision, hash(external));
    await api('/api/apply', 'POST', {values: {}, baseRevision: state.revision});
    state = await api('/api/state');
    assert.deepEqual(state.values, {});
  });

  await check('方案保存/读取/删除、中文名、路径字符过滤且不写游戏默认值', async () => {
    const values = {'battle/characters/player/speed': 920};
    await api('/api/presets', 'POST', {name: '测试方案', values});
    assert.ok((await api('/api/presets')).presets.includes('测试方案'));
    assert.deepEqual((await api('/api/presets?name=' + encodeURIComponent('测试方案'))).values, values);
    assert.deepEqual(JSON.parse(await fs.readFile(path.join(sandbox, 'tools/modifier/presets/测试方案.json'), 'utf8')).values, values);
    assert.deepEqual((await api('/api/state')).values, {});
    await api('/api/presets', 'POST', {name: '../越界\\方案:C*?', values}, 400);
    const names = (await api('/api/presets')).presets;
    for (const name of names) {
      assert.ok(!/[\\/:*?"<>|]/.test(name), '名称含路径字符：' + name);
      await api('/api/presets', 'DELETE', {name});
    }
    assert.deepEqual((await api('/api/presets')).presets, []);
    await api('/api/presets', 'POST', {name: '非法内容', values: {'battle/not-real': 3}}, 400);
    assert.deepEqual(await snapshot(sandbox, protectedPaths.slice(0, 2)), defaultsBefore);
  });

  await check('帧数编辑后恢复：四段都回默认就不留残余，别的段改过就保留', () => {
    const startup = model.items.find(item => item.path === 'battle/moves/light_1/startupSpeed');
    const active = model.items.find(item => item.path === 'battle/moves/light_1/activeSpeed');
    const base = lib.moveFrames(model, {}, 'light_1');
    const one = lib.editValues(model, {}, startup, base.startup + 3);
    assert.deepEqual(lib.resetValue(model, one, startup), {});
    const two = lib.editValues(model, one, active, base.active + 2);
    const partial = lib.resetValue(model, two, startup);
    const frames = lib.moveFrames(model, partial, 'light_1');
    assert.equal(frames.startup, base.startup);
    assert.equal(frames.active, base.active + 2);
    assert.equal(frames.recovery, base.recovery);
    assert.equal(frames.tail, base.tail);
    assert.deepEqual(lib.resetValue(model, partial, active), {});
  });

  await check('linked 按默认值比例、bool和零默认值同步；恢复删除对应值', () => {
    const main = model.items.find(item => item.path === 'battle/moves/dash_slash/hitbox/width');
    assert.ok(main);
    const linkedPath = 'battle/moves/dash_slash_left/hitbox/width';
    const values = lib.editValues(model, {}, main, main.defaultValue * 1.5);
    assert.equal(values[main.path], main.defaultValue * 1.5);
    assert.equal(values[linkedPath], resolvePath({battle}, linkedPath) * 1.5);
    const boolItem = model.items.find(item => item.path === 'battle/moves/dash_slash/forcesLaunch');
    const boolValues = lib.editValues(model, {}, boolItem, !boolItem.defaultValue);
    assert.equal(boolValues['battle/moves/dash_slash_left/forcesLaunch'], !boolItem.defaultValue);
    const reset = lib.resetValue(model, values, main);
    assert.ok(!Object.hasOwn(reset, main.path));
    assert.ok(!Object.hasOwn(reset, linkedPath));
    const zeroBattle = structuredClone(battle);
    zeroBattle.moves.find(move => move.id === 'dash_slash').damage = 0;
    const zeroModel = lib.createModel(catalog, {battle: zeroBattle, encounters});
    const zeroItem = zeroModel.items.find(item => item.path === 'battle/moves/dash_slash/damage');
    assert.equal(lib.editValues(zeroModel, {}, zeroItem, 21)['battle/moves/dash_slash_left/damage'], 21);
  });

  await check('jumpHeight 使用当前达峰时间、scale 正反转换', () => {
    const jump = model.items.find(item => item.derive === 'jumpHeight');
    const values = {'battle/characters/player/jumpTimeToPeak': 0.4};
    const speed = resolvePath({battle}, jump.path);
    assert.equal(lib.displayValue(model, values, jump), Math.round(speed * 0.4 * 0.5 * 1000) / 1000);
    const next = lib.editValues(model, values, jump, 300);
    assert.equal(next[jump.path], 1500);
    assert.equal(lib.displayValue(model, next, jump), 300);
    for (const item of model.items.filter(item => item.scale)) {
      assert.equal(lib.displayValue(model, {}, item), Math.round(item.defaultValue * item.scale * 1000) / 1000, item.path);
      const display = item.defaultValue * item.scale + 7;
      const edited = lib.editValues(model, {}, item, display);
      assert.equal(edited[item.path], display / item.scale, item.path);
      assert.ok(Math.abs(lib.displayValue(model, edited, item) - display) <= 0.0005, item.path);
    }
  });

  await check('所有非burst招式可编辑阶段1到30帧逐一反算，零时长不可编辑', () => {
    let count = 0;
    let skips = 0;
    for (const source of battle.moves) {
      if (source.burstFrameStart !== undefined && Math.abs((source.burstSpeed ?? 1) - 1) > 0.0001) continue;
      const timing = lib.timingFor(battle, source);
      for (const phase of ['startup', 'active', 'recovery', 'tail']) {
        if (!lib.phaseEditable(timing, phase)) {
          skips++;
          console.log('SKIP 不可编辑动画段：' + source.id + '/' + phase);
          continue;
        }
        for (let n = 1; n <= 30; n++) {
          const speed = lib.speedForFrames(timing, phase, n);
          assert.ok(Number.isFinite(speed) && speed > 0, source.id + '/' + phase + '/' + n);
          const result = lib.frames(timing, {...source, [phase + 'Speed']: speed});
          assert.equal(result[phase], n, source.id + '/' + phase + '/' + n + '，速度=' + speed);
          count++;
        }
      }
    }
    assert.ok(count > 1000);
    assert.ok(skips >= 2);
    const plunge = battle.moves.find(move => move.id === 'air_plunge');
    assert.equal(lib.phaseEditable(lib.timingFor(battle, plunge), 'startup'), false);
    assert.equal(lib.phaseEditable(lib.timingFor(battle, plunge), 'recovery'), false);
    console.log('INFO 阶段反算 ' + count + ' 次；不可编辑段 ' + skips + ' 个');
  });

  await check('界面阶段写回1到30帧且其他阶段帧数保持', () => {
    let count = 0;
    for (const item of model.items.filter(item => item.phase)) {
      const move = model.moves.find(move => move.id === item.entityId);
      if (!lib.phaseEditable(move.timing, item.phase)) continue;
      const before = lib.moveFrames(model, {}, move.id);
      for (let n = 1; n <= 30; n++) {
        const values = lib.editValues(model, {}, item, n);
        const after = lib.moveFrames(model, values, move.id);
        assert.equal(after[item.phase], n, move.id + '/' + item.phase + '/' + n);
        for (const phase of lib.phases) if (phase !== item.phase) assert.equal(after[phase], before[phase], move.id + '/' + item.phase + '连带改变' + phase);
        count++;
      }
    }
    assert.ok(count >= 900);
    console.log('INFO 界面阶段写回 ' + count + ' 次');
  });

  await check('ticks和四速度全1分支覆盖缺失/非正durationTicks与animationSpeed', () => {
    const synthetic = {
      settings: {startupSpeedMultiplier: 1, recoverySpeedMultiplier: 1},
      characters: [{id: 'player', sprite: {animations: {sample: {fps: 20, frames: [
        {}, {durationTicks: 2}, {durationTicks: 0}, {durationTicks: -4}, {durationTicks: '2'}, {durationTicks: 3},
      ]}}}}],
    };
    const source = {id: 'probe', animation: 'sample', animationSpeed: 2, syncAnimation: true, activeFrameStart: 1, activeFrameEnd: 2, chainFrame: 4};
    const timing = lib.timingFor(synthetic, source);
    assert.deepEqual(timing.raw, {duration: 9 / 40, start: 1 / 40, end: 4 / 40, chain: 5 / 40});
    assert.deepEqual(lib.frames(timing, source), {startup: 2, active: 4, recovery: 2, tail: 6, total: 14});
    assert.deepEqual(lib.frames(timing, {...source, startupSpeed: 2, activeSpeed: 2, recoverySpeed: 2, tailSpeed: 2}),
      {startup: 1, active: 3, recovery: 1, tail: 3, total: 8});
    const editBattle = {...synthetic, moves: [source]};
    const editCatalog = {pages: [{id: 'moves', template: 'moves', moves: [{id: source.id}], sections: [{title: '快慢', items: lib.phases.map(phase => ({phase}))}]}]};
    const editModel = lib.createModel(editCatalog, {battle: editBattle, encounters});
    const recoveryItem = editModel.items.find(item => item.phase === 'recovery');
    const edited = lib.editValues(editModel, {}, recoveryItem, 8);
    assert.equal(lib.moveFrames(editModel, edited, source.id).recovery, 8);
    assert.equal(lib.moveFrames(editModel, edited, source.id).tail, 6, 'tailSpeed缺省不应随修改recoverySpeed改变');
    const multipliers = structuredClone(synthetic);
    multipliers.settings = {startupSpeedMultiplier: 2, recoverySpeedMultiplier: 4};
    const withMultipliers = lib.frames(lib.timingFor(multipliers, source), {...source, recoverySpeed: 0.5});
    assert.deepEqual(withMultipliers, {startup: 1, active: 5, recovery: 1, tail: 3, total: 10});
  });

  await check('真实引擎逐招比对全部非burst帧数', async () => {
    const godot = path.join(root, 'engine/Godot_v4.7.2-stable_win64_console.exe');
    try { await fs.access(godot); } catch { console.log('SKIP 真实引擎不存在：' + godot); return; }
    const {stdout, stderr} = await runFile(godot, ['--headless', '--path', root, '--log-file', path.join(sandbox, 'godot-dump.log'), '--script', 'res://tests/dev/modifier_dump_moves.gd'], {cwd: root, windowsHide: true, timeout: 45000, maxBuffer: 8 * 1024 * 1024});
    const line = stdout.split(/\r?\n/).find(value => value.startsWith('MODIFIER_MOVES_JSON:'));
    assert.ok(line, '引擎未导出JSON：' + stdout + stderr);
    const engine = JSON.parse(line.slice('MODIFIER_MOVES_JSON:'.length));
    let compared = 0;
    for (const source of battle.moves) {
      if (source.burstFrameStart !== undefined && Math.abs((source.burstSpeed ?? 1) - 1) > 0.0001) continue;
      assert.ok(engine[source.id], source.id + ' 引擎缺失');
      const actual = lib.frames(lib.timingFor(battle, source), source);
      const expected = engine[source.id];
      assert.deepEqual(actual, {
        startup: expected.startup_frames, active: expected.active_frames,
        recovery: expected.cancel_frame, tail: expected.recovery_frames - expected.cancel_frame,
        total: expected.startup_frames + expected.active_frames + expected.recovery_frames,
      }, source.id);
      compared++;
    }
    assert.equal(compared, battle.moves.filter(move => move.burstFrameStart === undefined || Math.abs((move.burstSpeed ?? 1) - 1) <= 0.0001).length);
    console.log('INFO 真实引擎逐招一致：' + compared + ' 招');
  });

  await check('隔离验证Windows taskkill使用/T/F且先停止旧游戏再启动新场景', async () => {
    if (process.platform !== 'win32') { const error = new Error('仅Windows命令契约'); error.code = 'TEST_SKIP'; throw error; }
    const require = createRequire(import.meta.url);
    const childProcess = require('node:child_process');
    const {EventEmitter} = require('node:events');
    const gamePath = require.resolve(path.join(root, 'tools/modifier/lib/game.js'));
    const previous = require.cache[gamePath];
    const originalSpawn = childProcess.spawn;
    const events = [];
    let owned;
    let nextPid = 100000;
    childProcess.spawn = (command, args) => {
      const child = new EventEmitter();
      child.stdout = new EventEmitter();
      child.stderr = new EventEmitter();
      child.pid = ++nextPid;
      child.exitCode = null;
      child.signalCode = null;
      child.kill = () => { throw new Error('不能使用只终止父进程的降级'); };
      if (command === 'taskkill.exe') {
        assert.deepEqual(args, ['/PID', String(owned.pid), '/T', '/F']);
        events.push('stop:' + owned.pid);
        queueMicrotask(() => { owned.exitCode = 0; owned.emit('exit', 0); child.exitCode = 0; child.emit('exit', 0); });
      } else {
        const previousPid = owned?.pid;
        events.push('launch:' + child.pid);
        if (previousPid) assert.ok(events.includes('stop:' + previousPid));
        owned = child;
        queueMicrotask(() => child.emit('spawn'));
      }
      return child;
    };
    delete require.cache[gamePath];
    try {
      const {gameManager} = require(gamePath);
      const manager = gameManager(sandbox, path.join(sandbox, 'fake.exe'));
      const first = await manager.launch('rain');
      assert.equal((await manager.launch('rain')).pid, first.pid);
      const second = await manager.launch('training');
      assert.notEqual(second.pid, first.pid);
      await manager.stop();
      assert.equal(manager.status().running, false);
      assert.deepEqual(events, ['launch:' + first.pid, 'stop:' + first.pid, 'launch:' + second.pid, 'stop:' + second.pid]);
    } finally {
      childProcess.spawn = originalSpawn;
      delete require.cache[gamePath];
      if (previous) require.cache[gamePath] = previous;
    }
  });

  await check('launch同场景复用、跨场景结束旧进程、stop只结束自有进程', async () => {
    const foreign = spawn(node, ['-e', 'setInterval(()=>{},1000)'], {windowsHide: true, stdio: 'ignore'});
    fakePids.add(foreign.pid);
    try {
      await api('/api/game/launch', 'POST', {scene: 'invalid'}, 400);
      const launched = await api('/api/game/launch', 'POST', {scene: 'rain'});
      const first = launched.game || launched;
      assert.equal(first.running, true);
      assert.equal(first.scene, 'rain');
      fakePids.add(first.pid);
      await waitFor(async () => {
        try { return (await fs.readFile(path.join(sandbox, 'fake-launches.jsonl'), 'utf8')).trim().length > 0; } catch { return false; }
      }, '假Godot执行');
      let launches = (await fs.readFile(path.join(sandbox, 'fake-launches.jsonl'), 'utf8')).trim().split(/\r?\n/).map(JSON.parse);
      fakePids.add(launches[0].pid);
      fakePids.add(launches[0].childPid);
      assert.ok(launches[0].args.includes('res://scenes/rain_trial.tscn'));
      assert.ok(launches[0].args.includes(sandbox));
      const same = await api('/api/game/launch', 'POST', {scene: 'rain'});
      assert.equal((same.game || same).pid, first.pid);
      const switching = await fetch(base + '/api/game/launch', {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({scene: 'training'}), signal: AbortSignal.timeout(10000)});
      const other = await switching.json();
      if (switching.status === 500 && /无法结束修改器启动的游戏|taskkill|拒绝访问/.test(other.error || '')) {
        const still = (await api('/api/state')).game;
        assert.equal(still.running, true);
        assert.equal(still.pid, first.pid);
        assert.equal(still.scene, 'rain');
        assert.equal(alive(foreign.pid), true);
        assert.equal(alive(launches[0].childPid), true);
        const error = new Error('当前系统taskkill权限受限；已验证launch与同场景PID复用、失败后保留旧场景且不误杀外部进程；跨场景/停止整树未验证');
        error.code = 'TEST_SKIP';
        throw error;
      }
      assert.equal(switching.status, 200, JSON.stringify(other));
      const second = other.game || other;
      assert.equal(second.scene, 'training');
      assert.notEqual(second.pid, first.pid);
      fakePids.add(second.pid);
      await waitFor(() => !alive(first.pid) && !alive(launches[0].pid) && !alive(launches[0].childPid), '旧场景进程树结束');
      await waitFor(async () => (await fs.readFile(path.join(sandbox, 'fake-launches.jsonl'), 'utf8')).trim().split(/\r?\n/).length === 2, '训练场假Godot执行');
      launches = (await fs.readFile(path.join(sandbox, 'fake-launches.jsonl'), 'utf8')).trim().split(/\r?\n/).map(JSON.parse);
      const child = launches[1];
      fakePids.add(child.pid);
      fakePids.add(child.childPid);
      assert.ok(child.args.includes('res://scenes/training.tscn'));
      await api('/api/game/stop', 'POST', {});
      await waitFor(() => !alive(second.pid) && !alive(child.pid) && !alive(child.childPid), '停止自有进程树');
      assert.equal((await api('/api/state')).game.running, false);
      assert.equal(alive(foreign.pid), true, '误结束外部进程');
      await fs.access(path.join(sandbox, '.runtime/modifier-game.log'));
      await api('/api/game/stop', 'POST', {});
    } catch (error) {
      if (error.code === 'TEST_SKIP') throw error;
      const log = await fs.readFile(path.join(sandbox, '.runtime/modifier-game.log'), 'utf8').catch(() => '无日志');
      throw new Error(error.message + '\n假Godot日志：' + log);
    } finally { await killTree(foreign.pid); }
  });
} catch (error) {
  failed++;
  console.error('FAIL 测试准备或执行异常\n' + (error.stack || error) + '\n服务输出：' + serverOutput);
} finally {
  if (base) { try { await api('/api/game/stop', 'POST', {}); } catch {} }
  for (const pid of fakePids) await killTree(pid);
  if (server?.pid) {
    const exited = new Promise(resolve => { if (server.exitCode !== null) resolve(); else server.once('exit', resolve); });
    await killTree(server.pid);
    await Promise.race([exited, sleep(3000)]);
  }
  await check('场景：真实布局进模型，改动校验，导入图片落在指定目录', async () => {
    const require = createRequire(import.meta.url);
    const {sceneManager} = require(path.join(root, 'tools/modifier/lib/scene.js'));
    const {validateValues} = require(path.join(root, 'tools/modifier/lib/validation.js'));
    const docs = await sceneManager(root).documents();
    const sceneModel = lib.createModel(catalog, {battle, encounters, ...docs});
    const names = docs.layout.sections.map(s => s.name);
    assert.deepEqual(sceneModel.defaults['layout/sections/' + names[0] + '/platforms'], docs.layout.sections[0].platforms);
    // 斜坡、有没有、挡不挡
    const slopeKey = 'layout/sections/' + names[0] + '/slopes', platKey = 'layout/sections/' + names[0] + '/platforms', blockKey = 'layout/sections/' + names[0] + '/blocks';
    validateValues(sceneModel, {[slopeKey]: [[0, 580, 400, 400, 'steps'], [500, 400, 900, 580, 'steps', {solid: true, off: true}]]}, {});
    validateValues(sceneModel, {[platKey]: [[0, 300, 300, 'ring', {solid: true, bottom: 580}]], [blockKey]: [[0, 300, 470, 'steps', {pass: true}], [400, 440, 300, 'stone', {bottom: 560}]]}, {});
    assert.throws(() => validateValues(sceneModel, {[slopeKey]: [[400, 580, 0, 400, 'steps']]}, {}), /格式不对/);
    assert.throws(() => validateValues(sceneModel, {[platKey]: [[0, 300, 300, 'ring', {bottom: 200}]]}, {}), /格式不对/);
    assert.throws(() => validateValues(sceneModel, {[blockKey]: [[0, 300, 470, 'steps', {what: true}]]}, {}), /格式不对/);
    assert.deepEqual(lib.pieceMeta({w: 100, attach: [0, 100], stand: [], blocks: [], lamps: [], slopes: [[10, 500, 40, 400, 'steps']]}, true).slopes, [[60, 400, 90, 500, 'steps']]);
    assert.equal(sceneModel.defaults['layout/backdrop/far/scroll'], 0.3);
    assert.equal(sceneModel.defaults['scene/plan/0'].items.every(i => Number.isFinite(i.x) && typeof i.mirror === 'boolean'), true);
    const key = 'layout/sections/' + names[0] + '/';
    const ok = {[key + 'platforms']: [[0, 100, 300, 'ring']], [key + 'spawns']: [[1, 580]], [key + 'lamps']: [[1, 580, 'street', 200]], [key + 'foreground']: [[1, 'sign']], 'layout/backdrop/far/tex': 'res://assets/image/rain_street/edits/a.png', 'layout/backdrop/rain/drops': 100, 'layout/backdrop/depth': [{tex: 'res://assets/image/rain_street/a.png', scroll: 0.5, bottom: 400}], 'scene/plan/0': sceneModel.defaults['scene/plan/0']};
    assert.doesNotThrow(() => validateValues(sceneModel, ok, encounters.kinds));
    for (const wrong of [{[key + 'platforms']: [[100, 0, 300, 'ring']]}, {[key + 'spawns']: [[1]]}, {[key + 'art']: {near: 'res://../../secret.png', x0: 0, y0: 0, width: 1}}, {'layout/backdrop/far/tex': 'C:/secret.png'}, {'layout/backdrop/rain/drops': 'x'}, {'scene/plan/0': {items: 1}}])
      assert.throws(() => validateValues(sceneModel, wrong, encounters.kinds), undefined, JSON.stringify(wrong));
    const box = path.join(sandbox, 'scene-box');
    await fs.mkdir(path.join(box, 'docs/视觉设计/雨夜河岸街/素材库'), {recursive: true});
    await fs.writeFile(path.join(box, 'docs/视觉设计/雨夜河岸街/素材库/kit.json'), JSON.stringify({px_per_world: 0.5, street: 580, pieces: {}}));
    const png = Buffer.alloc(32); png.write('PNG', 'latin1'); png.writeUInt32BE(100, 16); png.writeUInt32BE(50, 20);
    const manager = sceneManager(box);
    const layer = await manager.importImage({kind: 'layer', name: '../我的 天空.png', data: png.toString('base64')});
    assert.ok(layer.tex.startsWith('res://assets/image/rain_street/edits/layer_') && layer.tex.endsWith('.png') && !layer.tex.includes('..'));
    const piece = (await manager.importImage({kind: 'piece', name: '楼.png', data: png.toString('base64')})).piece;
    assert.deepEqual([piece.w, piece.h, piece.top], [200, 100, 476]);
    assert.ok((await manager.info()).pieces.some(p => p.id === piece.id && p.imported));
    await assert.rejects(manager.importImage({kind: 'layer', name: 'x', data: Buffer.from('nope').toString('base64')}));
    await assert.rejects(manager.readImage('assets/data/../../secret.png'));
    await assert.rejects(manager.readImage('assets/data/battle.json'));
  });
  await check('真实 battle.json、encounters.json 和 tuning.json SHA256/存在状态完全未变', async () => {
    assert.deepEqual(await snapshot(root, protectedPaths), original);
  });
  try {
    const target = path.resolve(sandbox);
    const temp = path.resolve(os.tmpdir());
    assert.ok(target.startsWith(temp + path.sep) && path.basename(target).startsWith('nightcrow-modifier-test-'));
    await fs.rm(target, {recursive: true, force: true, maxRetries: 3, retryDelay: 200});
  } catch (error) { failed++; console.error('FAIL 清理沙盒：' + error.message); }
}
console.log('RESULT ' + passed + ' passed, ' + failed + ' failed, ' + skipped + ' skipped');
if (failed) process.exitCode = 1;
