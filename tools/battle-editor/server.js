'use strict';

const http = require('node:http');
const crypto = require('node:crypto');
const {spawn} = require('node:child_process');
const fs = require('node:fs/promises');
const {existsSync, statSync} = require('node:fs');
const path = require('node:path');
const { URL } = require('node:url');
const {importFrameBaker} = require('./framebaker-import');

const DEFAULT_ROOT = path.resolve(__dirname, '..', '..');
const MAX_BODY_BYTES = 12 * 1024 * 1024;
const CONFIG_RELATIVE = path.join('assets', 'data', 'battle.json');

function parseArgs(argv) {
    const result = {root: DEFAULT_ROOT, host: '127.0.0.1', port: 4329};
    for (let index = 0; index < argv.length; index += 1) {
        const argument = argv[index];
        if (argument === '--root' && argv[index + 1]) {
            result.root = path.resolve(argv[++index]);
        } else if (argument === '--host' && argv[index + 1]) {
            result.host = argv[++index];
        } else if (argument === '--port' && argv[index + 1]) {
            result.port = Number(argv[++index]);
        }
    }
    if (!Number.isInteger(result.port) || result.port < 1 || result.port > 65535) {
        result.port = 4329;
    }
    return result;
}

const options = parseArgs(process.argv.slice(2));
const projectRoot = options.root;
const configPath = path.join(projectRoot, CONFIG_RELATIVE);
const editorProjectPath = path.join(projectRoot, 'assets', 'data', 'editor-project.json');
const assetsRoot = path.join(projectRoot, 'assets');
const publicRoot = path.join(__dirname, 'public');
const distRoot = path.join(__dirname, 'dist');
const backupRoot = path.join(projectRoot, 'assets', 'data', 'backups');
const trashRoot = path.join(assetsRoot, '.trash');
const godotPath = path.join(projectRoot, 'engine', 'Godot_v4.7.2-stable_win64_console.exe');
const runtimeRoot = path.join(projectRoot, '.runtime');
let gameChild = null;

const mimeTypes = {
    '.css': 'text/css; charset=utf-8',
    '.gif': 'image/gif',
    '.html': 'text/html; charset=utf-8',
    '.ico': 'image/x-icon',
    '.jpeg': 'image/jpeg',
    '.jpg': 'image/jpeg',
    '.js': 'text/javascript; charset=utf-8',
    '.json': 'application/json; charset=utf-8',
    '.mp3': 'audio/mpeg',
    '.ogg': 'audio/ogg',
    '.png': 'image/png',
    '.svg': 'image/svg+xml',
    '.wav': 'audio/wav',
    '.webm': 'video/webm',
    '.woff': 'font/woff',
    '.woff2': 'font/woff2'
};

const uploadDirectories = {
    image: 'image',
    audio: 'audio',
    video: 'video',
    model: 'model',
    data: 'data',
    misc: 'misc'
};

let writeQueue = Promise.resolve();

function sendJson(response, statusCode, payload) {
    const body = JSON.stringify(payload);
    response.writeHead(statusCode, {
        'X-Content-Type-Options': 'nosniff',
        'Cache-Control': 'no-store',
        'Content-Type': 'application/json; charset=utf-8',
        'Content-Length': Buffer.byteLength(body)
    });
    response.end(body);
}

function sendText(response, statusCode, body, contentType = 'text/plain; charset=utf-8') {
    response.writeHead(statusCode, {
        'X-Content-Type-Options': 'nosniff',
        'Content-Type': contentType,
        'Content-Length': Buffer.byteLength(body)
    });
    response.end(body);
}

function fail(response, statusCode, message, details = undefined) {
    sendJson(response, statusCode, {ok: false, error: message, details});
}

function isObject(value) {
    return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function isFiniteNumber(value) {
    return typeof value === 'number' && Number.isFinite(value);
}

function addNumberRule(errors, value, label, minimum, maximum) {
    if (!isFiniteNumber(value)) {
        errors.push(`${label} 必须是数字`);
        return;
    }
    if (minimum !== undefined && value < minimum) {
        errors.push(`${label} 不能小于 ${minimum}`);
    }
    if (maximum !== undefined && value > maximum) {
        errors.push(`${label} 不能大于 ${maximum}`);
    }
}

function addOptionalNumberRule(errors, value, label, minimum, maximum) {
    if (value !== undefined) {
        addNumberRule(errors, value, label, minimum, maximum);
    }
}

function addBooleanRule(errors, value, label) {
    if (value !== undefined && typeof value !== 'boolean') {
        errors.push(`${label} 必须是布尔值`);
    }
}

function safeRelativePath(relativePath) {
    if (typeof relativePath !== 'string' || relativePath.trim() === '') {
        return null;
    }
    const normalized = relativePath.replaceAll('\\', '/');
    if (normalized.includes('\0') || normalized.includes(':') || normalized.startsWith('/') || normalized.split('/').some((part) => part === '..' || part === '.')) {
        return null;
    }
    if (path.posix.isAbsolute(normalized)) {
        return null;
    }
    return normalized;
}

function resolveInside(root, relativePath) {
    const safePath = safeRelativePath(relativePath);
    if (!safePath) {
        return null;
    }
    const resolved = path.resolve(root, safePath);
    const rootWithSeparator = root.endsWith(path.sep) ? root : `${root}${path.sep}`;
    return resolved === root || resolved.startsWith(rootWithSeparator) ? resolved : null;
}

function assetUrl(relativePath) {
    return `/project-assets/${relativePath.split('/').map((part) => encodeURIComponent(part)).join('/')}`;
}

async function gameStatus() {
    try {
        const value = await readJsonFile(path.join(runtimeRoot, 'game.json'));
        const recent = Date.now() - value.heartbeat < 2500;
        const sameRoot = path.resolve(value.projectRoot).toLowerCase() === projectRoot.toLowerCase();
        let alive=false;
        if(recent&&sameRoot&&Number.isInteger(value.pid)) {try{process.kill(value.pid,0);alive=true;}catch{}}
        return {process_alive: alive, pid: value.pid, engine: 'Godot', projectRoot};
    } catch { return {process_alive: false, engine: 'Godot', projectRoot}; }
}
async function startOrRefreshPreview() {
    const status = await gameStatus();
    if (status.process_alive) return status;
    if (gameChild && gameChild.exitCode === null) return {process_alive: true, pid: gameChild.pid, engine: 'Godot'};
    if (!existsSync(godotPath)) throw new Error('缺少随项目附带的 Godot');
    await fs.mkdir(runtimeRoot, {recursive: true});
    const args = ['--path', projectRoot];
    if (process.env.NIGHTCROW_TEST_HEADLESS === '1') args.unshift('--headless');
    gameChild = spawn(godotPath, args, {cwd: projectRoot, windowsHide: true, stdio: ['ignore','pipe','pipe']});
    const child = gameChild;
    let tail = '';
    const capture = chunk => { tail = (tail + chunk.toString()).slice(-24000); fs.writeFile(path.join(runtimeRoot,'game.log'), tail).catch(()=>{}); };
    child.stdout.on('data', capture); child.stderr.on('data', capture);
    await new Promise((resolve,reject) => { child.once('spawn',resolve); child.once('error',reject); });
    for (let i=0;i<60;i++) {
        await new Promise(resolve=>setTimeout(resolve,100));
        if (child.exitCode !== null) throw new Error('Godot 启动失败：'+tail.slice(-1000));
        const current = await gameStatus();
        if (current.process_alive) return current;
    }
    throw new Error('Godot 启动超时，请查看 .runtime/game.log');
}
async function stopGame() {
    const status = await gameStatus();
    if (status.process_alive) await fs.writeFile(path.join(runtimeRoot,`stop-${status.pid}.request`), 'stop');
    for (let i=0;i<25;i++) {
        await new Promise(resolve=>setTimeout(resolve,100));
        if (!(await gameStatus()).process_alive) break;
    }
    return await gameStatus();
}

function validateAssetReference(reference, label, warnings) {
    const safePath = safeRelativePath(reference);
    if (!safePath) {
        warnings.push(`${label} 使用了不安全或空的资源路径`);
        return;
    }
    const absolute = resolveInside(assetsRoot, safePath);
    if (!absolute) {
        warnings.push(`${label} 超出了 assets 目录`);
    } else if (!existsSync(absolute) || !statSync(absolute).isFile()) {
        warnings.push(`${label} 找不到资源：${reference}`);
    }
}

function validateConfig(config) {
    const errors=[], warnings=[];
    if (!isObject(config)) return {ok:false,errors:['配置必须是对象'],warnings};
    const c=(config.characters||[]).find(c=>c.id==='player');
    const d=(config.characters||[]).find(c=>c.id==='dummy');
    if (!c || !d) errors.push('必须保留夜鸦角色和训练木桩');
    if (!config.stage?.spawn?.player || config.stage?.spawn?.enemies?.length!==1) errors.push('训练场必须有一个角色出生点和一个木桩出生点');
    const bounds=config.stage?.bounds||{};
    for (const key of ['left','right','floorY']) addNumberRule(errors,bounds[key],`场地 ${key}`,0,1280);
    if (bounds.right<=bounds.left) errors.push('场地右边必须大于左边');
    for(const point of [config.stage?.spawn?.player,...(config.stage?.spawn?.enemies||[])]) if(point) for(const key of ['x','y']) addNumberRule(errors,point[key],`出生点 ${key}`,0,1280);
    for(const key of ['characterSpeedMultiplier','jumpSpeedMultiplier','jumpGravityMultiplier']) addNumberRule(errors,config.settings?.[key],key,0.1,3);
    for(const key of ['hitstopMultiplier','shakeMultiplier','squashStrength']) addOptionalNumberRule(errors,config.feedback?.[key],key,0,key==='squashStrength'?1:3);
    addOptionalNumberRule(errors,config.feedback?.parryHitstop,'弹刀停顿',0,0.5);
    for(const [key,min,max] of [['shakeDecay',1,30],['maxShake',0,80],['shakePixelSnap',0,4]]) addOptionalNumberRule(errors,config.camera?.[key],key,min,max);
    for(const key of ['masterVolume','sfxVolume']) addOptionalNumberRule(errors,config.audio?.[key],key,0,1);
    for(const [key,asset] of Object.entries(config.audio?.events||{})) {
        if(asset && (!safeRelativePath(asset)||!existsSync(resolveInside(assetsRoot,asset)||'')||!/\.(wav|ogg|mp3)$/i.test(asset))) errors.push(`${key} 音效文件无效：${asset}`);
    }
    for(const [key,min,max] of [['attackBufferFrames',1,64],['holdToChargeFrames',3,60],['comboKeepFrames',1,180]]) addNumberRule(errors,config.runtime?.[key],key,min,max);
    for(const actor of config.characters||[]) {
        addNumberRule(errors,actor.maxHp,`${actor.name} 血量`,1,99999);
        if(actor.id==='player') {
            addNumberRule(errors,actor.sprite?.displayScale,'角色显示倍率',0.25,3);
            addNumberRule(errors,actor.speed,'跑动速度',1,3000);
            addNumberRule(errors,actor.jumpSpeed,'跳跃速度',1,3000);
            addNumberRule(errors,actor.maxJumps,'跳跃次数',1,6);
            addNumberRule(errors,actor.acceleration,'加速度',1,50000);
            addNumberRule(errors,actor.airControl,'空中转向',0,1);
            for(const key of ['jumpTimeToPeak','jumpTimeToDescent']) addNumberRule(errors,actor[key],key,0.05,2);
        }
        for(const group of [actor.sprite?.animations||{},actor.sprite?.effects||{}]) for(const [name,clip] of Object.entries(group)) {
            addNumberRule(errors,clip.fps,`${name} 播放帧率`,Number.MIN_VALUE,240);
            addBooleanRule(errors,clip.effectsBaked,`${name} effectsBaked`);
            if(clip.overlayEffect !== undefined && (typeof clip.overlayEffect !== 'string' || (clip.overlayEffect !== '' && !Object.prototype.hasOwnProperty.call(actor.sprite?.effects||{},clip.overlayEffect)))) errors.push(`${name} overlayEffect 必须引用当前角色的特效`);
            if(!Array.isArray(clip.frames)||!clip.frames.length) errors.push(`${name} 缺少动作帧`);
            for(const frame of clip.frames||[]) {
                if(frame.durationTicks !== undefined && (!isFiniteNumber(frame.durationTicks) || frame.durationTicks <= 0)) errors.push(`${name} durationTicks 必须是正数`);
                if(frame.blank) continue;
                if(!safeRelativePath(frame.asset)||!existsSync(resolveInside(assetsRoot,frame.asset)||'')) errors.push(`${name} 图片不存在：${frame.asset}`);
                if(!/\.(png|jpe?g)$/i.test(frame.asset||'')) errors.push(`${name} 动作图片须为 PNG/JPG`);
                for(const k of ['width','height']) addNumberRule(errors,frame[k],`${name} ${k}`,1,16384);
                for(const k of ['pivotX','pivotY']) addNumberRule(errors,frame[k],`${name} ${k}`,-20000,20000);
                if(frame.region) for(const k of ['x','y','width','height']) addNumberRule(errors,frame.region[k],`${name} 图集 ${k}`,k==='width'||k==='height'?1:0,32768);
            }
        }
    }
    const required=['light_1','light_2','light_3','charge_1','up_strike','air_up','ranged_1','parry_1'];
    if(new Set((config.moves||[]).map(m=>m.id)).size!==(config.moves||[]).length) errors.push('招式 ID 重复');
    for(const id of required) if(!(config.moves||[]).some(m=>m.id===id)) errors.push(`缺少基础招式 ${id}`);
    for(const m of config.moves||[]) {
        addNumberRule(errors,m.damage,`${m.name} 伤害`,0,9999);
        addNumberRule(errors,m.animationSpeed,`${m.name} 动作速度`,0.25,3);
        for(const k of ['hitstop','victimHitstop']) addNumberRule(errors,m[k],`${m.name} ${k}`,0,0.5);
        addOptionalNumberRule(errors,m.chargeHitstopBonus,`${m.name} 蓄力额外顿帧`,0,0.5);
        for(const k of ['squashX','squashY']) addOptionalNumberRule(errors,m[k],`${m.name} ${k}`,0.25,2);
        if(m.syncAnimation) {
            const clip=c?.sprite?.animations?.[m.animation];
            if(!clip) errors.push(`${m.name} 缺少动作 ${m.animation}`);
            else {
                const n=clip.frames.length;
                for(const k of ['activeFrameStart','activeFrameEnd','chainFrame']) addNumberRule(errors,m[k],`${m.name} ${k}`,0,k==='chainFrame'?n:n-1);
                if(m.activeFrameEnd<m.activeFrameStart) errors.push(`${m.name} 生效结束帧小于开始帧`);
                if(m.chainFrame<=m.activeFrameEnd) errors.push(`${m.name} 接招帧必须在生效结束帧之后`);
            }
        } else {
            addNumberRule(errors,m.duration,`${m.name} 时长`,0.016,10);
            if(!(m.activeStart>=0&&m.activeEnd>m.activeStart&&m.activeEnd<m.duration)) errors.push(`${m.name} 时间窗口无效`);
        }
        if(!m.hitbox||m.hitbox.width<=0||m.hitbox.height<=0) errors.push(`${m.name} 攻击框尺寸无效`);
        if(m.id==='charge_1'&&(!(m.minHold>=0)||m.maxHold<m.minHold)) errors.push('最长蓄力不能小于最短蓄力');
        if(m.id==='ranged_1') {addNumberRule(errors,m.projectile?.speed,'弹丸速度',1,5000);addNumberRule(errors,m.projectile?.life,'弹丸时长',0.05,10);}
    }
    return {ok:errors.length===0,errors,warnings,summary:{characters:config.characters?.length||0,moves:config.moves?.length||0}};
}

async function readJsonFile(filePath) {
    return JSON.parse(await fs.readFile(filePath, 'utf8'));
}
async function readRequestBody(request) {
    const chunks=[]; let total=0;
    for await (const chunk of request) {
        total+=chunk.length;
        if(total>MAX_BODY_BYTES) throw new Error('文件超过 12 MB，请缩小单张导入文件');
        chunks.push(chunk);
    }
    return Buffer.concat(chunks).toString('utf8');
}
async function readJsonBody(request) {
    return JSON.parse((await readRequestBody(request))||'{}');
}
function timestamp() {
    return new Date().toISOString().replaceAll(':', '-').replaceAll('.', '-');
}

async function backupConfig() {
    try {
        await fs.access(configPath);
    } catch {
        return null;
    }
    await fs.mkdir(backupRoot, {recursive: true});
    const backupPath = path.join(backupRoot, `battle-${timestamp()}-${crypto.randomBytes(3).toString('hex')}.json`);
    await fs.copyFile(configPath, backupPath);
    return path.relative(projectRoot, backupPath).replaceAll(path.sep, '/');
}

async function backupEditorProject() {
    try {
        await fs.access(editorProjectPath);
    } catch {
        return null;
    }
    await fs.mkdir(backupRoot, {recursive: true});
    const backupPath = path.join(backupRoot, `editor-project-${timestamp()}-${crypto.randomBytes(3).toString('hex')}.json`);
    await fs.copyFile(editorProjectPath, backupPath);
    return path.relative(projectRoot, backupPath).replaceAll(path.sep, '/');
}

async function writeConfig(config) {
    await writeJson(configPath, config);
}

async function writeJson(destination, value) {
    await fs.mkdir(path.dirname(destination), {recursive: true});
    const tempPath = `${destination}.${process.pid}.${crypto.randomBytes(4).toString('hex')}.tmp`;
    await fs.writeFile(tempPath, `${JSON.stringify(value, null, 2)}\n`, 'utf8');
    try {
        await fs.rename(tempPath, destination);
    } catch (error) {
        if (!['EEXIST', 'EPERM', 'EACCES'].includes(error.code)) throw error;
        await fs.copyFile(tempPath, destination);
    } finally {
        await fs.rm(tempPath, {force: true});
    }
}

function enqueueWrite(task) {
    const operation = writeQueue.then(task);
    writeQueue = operation.catch(() => {});
    return operation;
}

async function saveConfig(config) {
    return enqueueWrite(async () => {
        const backup = await backupConfig();
        await writeConfig(config);
        return {backup};
    });
}

async function saveEditorProject(project) {
    if (!isObject(project)) {
        throw new Error('编辑器项目必须是 JSON 对象');
    }
    return enqueueWrite(async () => {
        const backup = await backupEditorProject();
        await writeJson(editorProjectPath, project);
        return {backup};
    });
}

async function saveProject(config, project) {
    if (!isObject(project) || !isObject(project.workspace) || !isObject(project.documents)) throw new Error('编辑器项目结构无效');
    return enqueueWrite(async () => {
        const previous = await readJsonFile(configPath);
        const previousProject = await readJsonFile(editorProjectPath).catch((error) => {
            if (error.code !== 'ENOENT') throw error;
            return {schemaVersion: 1, workspace: {}, documents: {}};
        });
        const backup = `project-${timestamp()}-${crypto.randomBytes(3).toString('hex')}.json`;
        await writeJson(path.join(backupRoot, backup), {config: previous, project: previousProject});
        try {
            await writeConfig(config);
            await writeJson(editorProjectPath, project);
        } catch (error) {
            await writeConfig(previous);
            await writeJson(editorProjectPath, previousProject);
            throw error;
        }
        return {backup};
    });
}

async function listFiles(directory, relativeDirectory = '') {
    let entries;
    try {
        entries = await fs.readdir(directory, {withFileTypes: true});
    } catch {
        return [];
    }
    const files = [];
    for (const entry of entries) {
        const absolutePath = path.join(directory, entry.name);
        const relativePath = path.join(relativeDirectory, entry.name);
        if (entry.isDirectory()) {
            const normalizedDirectory = relativePath.replaceAll(path.sep, '/');
            if (normalizedDirectory === 'data/backups' || normalizedDirectory === '.trash') {
                continue;
            }
            files.push(...await listFiles(absolutePath, relativePath));
        } else if (entry.isFile()) {
            const info = await fs.stat(absolutePath);
            const normalized = relativePath.replaceAll(path.sep, '/');
            if (normalized.startsWith('data/')) {
                continue;
            }
            const extension = path.extname(entry.name).toLowerCase();
            const kind = ['.png', '.jpg', '.jpeg', '.gif', '.svg', '.webp'].includes(extension) ? 'image' : ['.mp3', '.ogg', '.wav', '.m4a'].includes(extension) ? 'audio' : ['.mp4', '.webm', '.mov'].includes(extension) ? 'video' : 'file';
            files.push({path: normalized, size: info.size, modifiedAt: info.mtime.toISOString(), extension, kind, previewable: kind !== 'file', url: assetUrl(normalized)});
        }
    }
    return files;
}

function decodeUploadData(value) {
    if (typeof value !== 'string' || value.length === 0) {
        throw new Error('contentBase64 必须是非空字符串');
    }
    const match = value.match(/^data:[^;]+;base64,(.*)$/s);
    const base64 = match ? match[1] : value;
    if (!/^[A-Za-z0-9+/=\r\n]+$/.test(base64)) {
        throw new Error('contentBase64 格式不正确');
    }
    const buffer = Buffer.from(base64, 'base64');
    if (buffer.length === 0) {
        throw new Error('上传文件为空');
    }
    return buffer;
}

async function handleApi(request, response, pathname) {
    if (request.method === 'POST' && pathname === '/api/framebaker/import') {
        try { sendJson(response, 200, await importFrameBaker(request, assetsRoot)); }
        catch (error) { fail(response, 400, `FrameBaker 导入失败：${error.message}`); }
        return;
    }
    if (request.method === 'GET' && pathname === '/api/backups') {
        const names = await fs.readdir(backupRoot).catch(() => []);
        const backups = await Promise.all(names.filter((name) => /^(battle|editor-project|project)-.*\.json$/.test(name)).map(async (name) => ({name, modifiedAt: (await fs.stat(path.join(backupRoot, name))).mtime.toISOString()})));
        sendJson(response, 200, {ok: true, backups: backups.sort((first, second) => second.modifiedAt.localeCompare(first.modifiedAt))});
        return;
    }
    if (request.method === 'GET' && pathname === '/api/backup') {
        const name = new URL(request.url, 'http://localhost').searchParams.get('name');
        if (!name || !/^(battle|editor-project|project)-[^/\\]+\.json$/.test(name)) { fail(response, 400, '备份名称无效'); return; }
        const destination = resolveInside(backupRoot, name);
        sendJson(response, 200, {ok: true, value: await readJsonFile(destination)});
        return;
    }
    if (request.method === 'GET' && pathname === '/api/trash') {
        const names = await fs.readdir(trashRoot).catch(() => []);
        const entries = [];
        for (const name of names.filter((name) => name.endsWith('.meta.json'))) {
            const entry = await readJsonFile(path.join(trashRoot, name));
            if (existsSync(path.join(trashRoot, entry.id))) entries.push(entry);
        }
        sendJson(response, 200, {ok: true, entries});
        return;
    }
    if (request.method === 'POST' && pathname === '/api/asset/restore') {
        const payload = await readJsonBody(request);
        const id = safeRelativePath(payload.id);
        if (!id || id.includes('/')) { fail(response, 400, '回收站 ID 无效'); return; }
        const entry = await readJsonFile(path.join(trashRoot, `${id}.meta.json`));
        const destination = resolveInside(assetsRoot, entry.path);
        if (!destination || entry.path.startsWith('.trash/') || entry.path.startsWith('data/')) { fail(response, 400, '恢复路径无效'); return; }
        await fs.mkdir(path.dirname(destination), {recursive: true});
        await fs.copyFile(path.join(trashRoot, id), destination, 1);
        await fs.unlink(path.join(trashRoot, id));
        await fs.unlink(path.join(trashRoot, `${id}.meta.json`));
        sendJson(response, 200, {ok: true, path: entry.path});
        return;
    }
    if (request.method === 'GET' && pathname === '/api/health') {
        sendJson(response, 200, {ok: true, engine: 'Godot', projectRoot, configPath: path.relative(projectRoot, configPath).replaceAll(path.sep, '/')});
        return;
    }
    if (request.method === 'GET' && pathname === '/api/config') {
        try {
            const config = await readJsonFile(configPath);
            sendJson(response, 200, {ok: true, config, validation: validateConfig(config)});
        } catch (error) {
            fail(response, 404, `读取配置失败：${error.message}`);
        }
        return;
    }
    if (request.method === 'GET' && pathname === '/api/editor-project') {
        try {
            const project = await readJsonFile(editorProjectPath);
            sendJson(response, 200, {ok: true, project});
        } catch (error) {
            if (error.code === 'ENOENT') {
                sendJson(response, 200, {ok: true, project: {schemaVersion: 1, workspace: {}, documents: {}}});
            } else {
                fail(response, 404, `读取编辑器项目失败：${error.message}`);
            }
        }
        return;
    }
    if (request.method === 'GET' && pathname === '/api/assets') {
        sendJson(response, 200, {ok: true, assets: await listFiles(assetsRoot)});
        return;
    }
    if (request.method === 'GET' && pathname === '/api/game/status') {
        try {
            sendJson(response, 200, {ok: true, status: await gameStatus()});
        } catch (error) {
            fail(response, 500, `读取游戏状态失败：${error.message}`);
        }
        return;
    }
    if (request.method === 'POST' && pathname === '/api/game/start') {
        try {
            const status = await startOrRefreshPreview();
            sendJson(response, 200, {ok: true, status, message: status.warning || '游戏预览已启动并加载最新配置'});
        } catch (error) {
            fail(response, 500, `启动游戏失败：${error.message}`);
        }
        return;
    }
    if (request.method === 'POST' && pathname === '/api/game/stop') {
        try {
            sendJson(response, 200, {ok: true, status: await stopGame(), message: '游戏预览已停止'});
        } catch (error) {
            fail(response, 500, `停止游戏失败：${error.message}`);
        }
        return;
    }
    if (request.method === 'POST' && pathname === '/api/validate') {
        try {
            const config = await readJsonBody(request);
            sendJson(response, 200, {ok: true, validation: validateConfig(config)});
        } catch (error) {
            fail(response, 400, error.message);
        }
        return;
    }
    if (request.method === 'POST' && pathname === '/api/config') {
        try {
            const config = await readJsonBody(request);
            const validation = validateConfig(config);
            if (!validation.ok) {
                sendJson(response, 400, {ok: false, error: '配置校验失败', validation});
                return;
            }
            const saved = await saveConfig(config);
            sendJson(response, 200, {ok: true, message: '配置已保存', backup: saved.backup, validation});
        } catch (error) {
            fail(response, 400, error.message);
        }
        return;
    }
    if (request.method === 'POST' && pathname === '/api/project/save') {
        try {
            const payload = await readJsonBody(request);
            const validation = validateConfig(payload.config);
            if (!validation.ok) { sendJson(response, 400, {ok: false, error: '配置校验失败', validation}); return; }
            const saved = await saveProject(payload.config, payload.project);
            sendJson(response, 200, {ok: true, ...saved, validation});
        } catch (error) { fail(response, 400, error.message); }
        return;
    }
    if (request.method === 'POST' && pathname === '/api/editor-project') {
        try {
            const project = await readJsonBody(request);
            const saved = await saveEditorProject(project);
            sendJson(response, 200, {ok: true, message: '编辑器项目已保存', backup: saved.backup});
        } catch (error) {
            fail(response, 400, error.message);
        }
        return;
    }
    if (request.method === 'POST' && pathname === '/api/upload') {
        try {
            const payload = await readJsonBody(request);
            const subdirectory = uploadDirectories[payload.category];
            if (!subdirectory) {
                throw new Error(`不支持的资源分类：${payload.category}`);
            }
            const filename = safeRelativePath(payload.filename);
            if (!filename || filename.endsWith('/')) {
                throw new Error('filename 不安全或为空');
            }
            let destination = resolveInside(path.join(assetsRoot, subdirectory), filename);
            if (!destination) {
                throw new Error('上传路径超出了目标资源目录');
            }
            const content = decodeUploadData(payload.contentBase64);
            await fs.mkdir(path.dirname(destination), {recursive: true});
            const original = destination;
            let counter = 0;
            while (true) {
                try { await fs.writeFile(destination, content, {flag: 'wx'}); break; }
                catch (error) {
                    if (error.code !== 'EEXIST' || counter >= 1000) throw error;
                    counter += 1;
                    const extension = path.extname(original);
                    destination = original.slice(0, original.length - extension.length) + `_${counter}` + extension;
                }
            }
            sendJson(response, 200, {
                ok: true,
                path: path.relative(assetsRoot, destination).replaceAll(path.sep, '/'),
                size: content.length
            });
        } catch (error) {
            fail(response, 400, error.message);
        }
        return;
    }
    if (request.method === 'POST' && pathname === '/api/asset/rename') {
        try {
            const payload = await readJsonBody(request);
            const oldPath = safeRelativePath(payload.path);
            const newName = safeRelativePath(payload.name);
            if (!oldPath || !newName || newName.includes('/')) {
                throw new Error('素材路径或新文件名不安全');
            }
            const source = resolveInside(assetsRoot, oldPath);
            const destination = source ? resolveInside(path.dirname(source), newName) : null;
            if (!source || !destination || oldPath.startsWith('data/') || oldPath.startsWith('.trash/')) {
                throw new Error('素材路径无效');
            }
            const sourceInfo = await fs.stat(source);
            if (!sourceInfo.isFile()) throw new Error('只能重命名文件素材');
            await fs.access(destination).then(() => { throw new Error('目标文件名已存在'); }).catch((error) => {
                if (error.code !== 'ENOENT') throw error;
            });
            const current = await readJsonFile(configPath);
            const newPath = path.relative(assetsRoot,destination).replaceAll(path.sep,'/');
            if(JSON.stringify(current).includes(JSON.stringify(oldPath))) {
                await fs.copyFile(source,destination);
                const rewrite=value=>typeof value==='string'?(value===oldPath?newPath:value):Array.isArray(value)?value.map(rewrite):isObject(value)?Object.fromEntries(Object.entries(value).map(([k,v])=>[k,rewrite(v)])):value;
                await saveConfig(rewrite(current));
            } else await fs.rename(source, destination);
            sendJson(response, 200, {ok: true, path: path.relative(assetsRoot, destination).replaceAll(path.sep, '/')});
        } catch (error) {
            fail(response, 400, `重命名素材失败：${error.message}`);
        }
        return;
    }
    if (request.method === 'POST' && pathname === '/api/asset/delete') {
        try {
            const payload = await readJsonBody(request);
            const relativePath = safeRelativePath(payload.path);
            const source = relativePath ? resolveInside(assetsRoot, relativePath) : null;
            if (!relativePath || !source || relativePath.startsWith('data/') || relativePath.startsWith('.trash/')) {
                throw new Error('素材路径无效');
            }
            const active = await readJsonFile(configPath);
            if (JSON.stringify(active).includes(JSON.stringify(relativePath))) throw new Error('该素材仍被动作使用，请先在动作工坊替换并保存');
            const sourceInfo = await fs.stat(source);
            if (!sourceInfo.isFile()) throw new Error('只能删除文件素材');
            await fs.mkdir(trashRoot, {recursive: true});
            const trashName = `${Date.now()}-${crypto.randomBytes(3).toString('hex')}-${path.basename(source)}`;
            const trashPath = path.join(trashRoot, trashName);
            await writeJson(`${trashPath}.meta.json`, {id: trashName, path: relativePath, deletedAt: new Date().toISOString()});
            await fs.rename(source, trashPath);
            sendJson(response, 200, {ok: true, trashPath: path.relative(projectRoot, trashPath).replaceAll(path.sep, '/')});
        } catch (error) {
            fail(response, 400, `删除素材失败：${error.message}`);
        }
        return;
    }
    fail(response, 404, '未找到 API 路由');
}

async function serveStatic(request, response, pathname) {
    if (pathname.startsWith('/project-assets/')) {
        const requestedAsset = decodeURIComponent(pathname.slice('/project-assets/'.length));
        const assetPath = resolveInside(assetsRoot, requestedAsset);
        if (!assetPath) {
            sendText(response, 403, 'Forbidden');
            return;
        }
        try {
            const info = await fs.stat(assetPath);
            if (!info.isFile()) {
                sendText(response, 404, 'Not found');
                return;
            }
            const content = await fs.readFile(assetPath);
            response.writeHead(200, {'Cache-Control': 'no-cache', 'Content-Type': mimeTypes[path.extname(assetPath).toLowerCase()] || 'application/octet-stream', 'Content-Length': content.length});
            response.end(content);
        } catch {
            sendText(response, 404, 'Not found');
        }
        return;
    }
    const requestedPath = pathname === '/' ? 'index.html' : pathname.slice(1);
    let frontendRoot = publicRoot;
    try {
        await fs.access(path.join(distRoot, 'index.html'));
        frontendRoot = distRoot;
    } catch {
        frontendRoot = publicRoot;
    }
    const filePath = resolveInside(frontendRoot, requestedPath);
    if (!filePath) {
        sendText(response, 403, 'Forbidden');
        return;
    }
    try {
        const info = await fs.stat(filePath);
        if (!info.isFile()) {
            sendText(response, 404, 'Not found');
            return;
        }
        const content = await fs.readFile(filePath);
        response.writeHead(200, {
            'Cache-Control': 'no-cache',
            'Content-Type': mimeTypes[path.extname(filePath).toLowerCase()] || 'application/octet-stream',
            'Content-Length': content.length
        });
        response.end(content);
    } catch {
        if (frontendRoot === distRoot && pathname !== '/') {
            const fallbackPath = path.join(distRoot, 'index.html');
            try {
                const content = await fs.readFile(fallbackPath);
                response.writeHead(200, {'Cache-Control': 'no-cache', 'Content-Type': 'text/html; charset=utf-8', 'Content-Length': content.length});
                response.end(content);
                return;
            } catch {
                // Fall through to the normal 404 response.
            }
        }
        sendText(response, 404, 'Not found');
    }
}

const server = http.createServer(async (request, response) => {
    const origin = request.headers.origin;
    const allowedOrigins = [`http://127.0.0.1:${options.port}`, `http://localhost:${options.port}`, 'http://127.0.0.1:5173', 'http://localhost:5173'];
    if (origin && !allowedOrigins.includes(origin)) { fail(response, 403, '拒绝来自其他网站的本地编辑器请求'); return; }
    const hostname = (request.headers.host || '').split(':')[0];
    if (!['127.0.0.1', 'localhost', options.host].includes(hostname)) { fail(response, 403, 'Host 无效'); return; }
    if (origin) response.setHeader('Access-Control-Allow-Origin', origin);
    if (request.method === 'OPTIONS') {
        response.writeHead(204, {
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
            'Access-Control-Allow-Origin': origin || `http://127.0.0.1:${options.port}`
        });
        response.end();
        return;
    }
    try {
        const url = new URL(request.url, `http://${request.headers.host || 'localhost'}`);
        if (url.pathname.startsWith('/api/')) {
            await handleApi(request, response, url.pathname);
        } else if (request.method === 'GET') {
            await serveStatic(request, response, url.pathname);
        } else {
            fail(response, 405, '只支持 GET、POST 和 OPTIONS');
        }
    } catch (error) {
        fail(response, 500, error.message);
    }
});

server.listen(options.port, options.host, () => {
    console.log(`Battle editor listening at http://${options.host}:${options.port}`);
    console.log(`Project root: ${projectRoot}`);
});

process.on('SIGINT', () => server.close(() => process.exit(0)));
process.on('SIGTERM', () => server.close(() => process.exit(0)));
