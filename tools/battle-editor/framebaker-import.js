'use strict';

const fs = require('node:fs/promises');
const path = require('node:path');
const crypto = require('node:crypto');
const {inflateSync, inflateRawSync} = require('node:zlib');

const MAX_ARCHIVE = 128 * 1024 * 1024;
const MAX_EXPANDED = 512 * 1024 * 1024;
const MAX_FILES = 4096;
const MAX_JSON = 8 * 1024 * 1024;
const utf8 = new TextDecoder('utf-8', {fatal: true});
const assert = (condition, message) => { if (!condition) throw new Error(message); };
const object = value => value && typeof value === 'object' && !Array.isArray(value);
const finite = value => typeof value === 'number' && Number.isFinite(value);
const integer = value => Number.isSafeInteger(value) && value >= 0;

const crcTable = Array.from({length: 256}, (_, index) => {
    let value = index;
    for (let bit = 0; bit < 8; bit++) value = (value >>> 1) ^ ((value & 1) ? 0xedb88320 : 0);
    return value >>> 0;
});
function crc32(data) {
    let value = 0xffffffff;
    for (const byte of data) value = (value >>> 8) ^ crcTable[(value ^ byte) & 255];
    return (value ^ 0xffffffff) >>> 0;
}

function safeName(name, directory = false) {
    assert(typeof name === 'string' && name.length > 0 && name.length <= 1024, '文件路径为空或过长');
    // Reject Windows aliases too: imports must have the same identity on every platform.
    assert(!/[\\\x00-\x1f\x7f:<>"|?*]/.test(name) && !name.startsWith('/'), '文件路径不安全');
    const parts = (directory && name.endsWith('/') ? name.slice(0, -1) : name).split('/');
    assert(parts.every(part => part && part !== '.' && part !== '..' && !/[. ]$/.test(part) && !/^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)/i.test(part)), '文件路径不安全');
    return parts.join('/');
}

function unzip(buffer) {
    assert(buffer.length >= 22 && buffer.length <= MAX_ARCHIVE, 'ZIP 大小无效（上限 128 MiB）');
    let end = -1;
    for (let i = buffer.length - 22; i >= Math.max(0, buffer.length - 65557); i--) {
        if (buffer.readUInt32LE(i) === 0x06054b50 && i + 22 + buffer.readUInt16LE(i + 20) === buffer.length) { end = i; break; }
    }
    assert(end >= 0, 'ZIP 目录缺失');
    const count = buffer.readUInt16LE(end + 10), size = buffer.readUInt32LE(end + 12), start = buffer.readUInt32LE(end + 16);
    assert(buffer.readUInt16LE(end + 4) === 0 && buffer.readUInt16LE(end + 6) === 0 && buffer.readUInt16LE(end + 8) === count, '不支持分卷 ZIP');
    assert(count > 0 && count <= MAX_FILES && start + size === end, 'ZIP 文件数量或目录无效');
    const files = new Map(), names = new Set(), ranges = [];
    let cursor = start, total = 0;
    for (let i = 0; i < count; i++) {
        assert(cursor + 46 <= end && buffer.readUInt32LE(cursor) === 0x02014b50, 'ZIP 目录损坏');
        const flags = buffer.readUInt16LE(cursor + 8), method = buffer.readUInt16LE(cursor + 10), crc = buffer.readUInt32LE(cursor + 16);
        const packedSize = buffer.readUInt32LE(cursor + 20), unpackedSize = buffer.readUInt32LE(cursor + 24);
        const nameSize = buffer.readUInt16LE(cursor + 28), extraSize = buffer.readUInt16LE(cursor + 30), commentSize = buffer.readUInt16LE(cursor + 32);
        const offset = buffer.readUInt32LE(cursor + 42), attributes = buffer.readUInt32LE(cursor + 38);
        assert(cursor + 46 + nameSize + extraSize + commentSize <= end && buffer.readUInt16LE(cursor + 34) === 0, 'ZIP 目录越界');
        assert(!(flags & ~0x808) && [0, 8].includes(method), '不支持加密或此 ZIP 压缩格式');
        const rawName = buffer.subarray(cursor + 46, cursor + 46 + nameSize), decoded = utf8.decode(rawName), directory = decoded.endsWith('/');
        const name = safeName(decoded, directory), identity = name.toLowerCase();
        assert(!names.has(identity), 'ZIP 内有重复路径'); names.add(identity);
        const unixType = (attributes >>> 16) & 0xf000;
        assert(unixType === 0 || unixType === (directory ? 0x4000 : 0x8000), 'ZIP 不允许链接或特殊文件');
        total += unpackedSize;
        assert(total <= MAX_EXPANDED, 'ZIP 解压超过 512 MiB');
        assert(offset + 30 <= start && buffer.readUInt32LE(offset) === 0x04034b50, 'ZIP 本地文件头无效');
        const localNameSize = buffer.readUInt16LE(offset + 26), localExtra = buffer.readUInt16LE(offset + 28), dataStart = offset + 30 + localNameSize + localExtra;
        assert(buffer.readUInt16LE(offset + 6) === flags && buffer.readUInt16LE(offset + 8) === method && dataStart + packedSize <= start, 'ZIP 文件数据越界或头不一致');
        assert(buffer.subarray(offset + 30, offset + 30 + localNameSize).equals(rawName), 'ZIP 文件名称不一致');
        if (!(flags & 8)) assert(buffer.readUInt32LE(offset + 14) === crc && buffer.readUInt32LE(offset + 18) === packedSize && buffer.readUInt32LE(offset + 22) === unpackedSize, 'ZIP 文件大小不一致');
        ranges.push([offset, dataStart + packedSize]);
        assert(!directory || unpackedSize === 0, 'ZIP 目录包含数据');
        if (!directory) {
            assert(/\.(png|frames\.json)$/i.test(name), 'ZIP 仅允许 PNG 和 .frames.json');
            assert(!/\.frames\.json$/i.test(name) || unpackedSize <= MAX_JSON, 'JSON 元数据过大');
            const packed = buffer.subarray(dataStart, dataStart + packedSize);
            const data = method === 0 ? packed : inflateRawSync(packed, {maxOutputLength: Math.max(1, unpackedSize)});
            assert(data.length === unpackedSize && crc32(data) === crc, 'ZIP 大小或 CRC 校验失败');
            files.set(name, data);
        }
        cursor += 46 + nameSize + extraSize + commentSize;
    }
    assert(cursor === end, 'ZIP 目录长度无效');
    ranges.sort((a, b) => a[0] - b[0]);
    assert(ranges.every((range, index) => index === 0 || range[0] >= ranges[index - 1][1]), 'ZIP 数据重叠');
    return files;
}

function decodeBase64(value) {
    assert(typeof value === 'string' && value.length > 0 && value.length % 4 === 0 && /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(value), '文件 Base64 无效');
    const result = Buffer.from(value, 'base64');
    assert(result.toString('base64') === value, '文件 Base64 无效');
    return result;
}

function parseFolder(payload) {
    assert(object(payload) && object(payload.metadata) && Array.isArray(payload.files) && payload.files.length > 0 && payload.files.length <= MAX_FILES, '需要 metadata 和 files（最多 4096 个）');
    const metadataFile = payload.metadataFile === undefined ? null : safeName(payload.metadataFile);
    assert(metadataFile === null || /\.frames\.json$/i.test(metadataFile), 'metadataFile 必须是 .frames.json 路径');
    const files = new Map(), names = new Set();
    let total = 0;
    for (const file of payload.files) {
        assert(object(file), '文件条目无效');
        const name = safeName(file.name), identity = name.toLowerCase();
        assert(!names.has(identity) && /\.png$/i.test(name), '文件夹只允许不重名的 PNG；metadata 只提供一次'); names.add(identity);
        const data = decodeBase64(file.contentBase64); total += data.length;
        assert(total <= MAX_EXPANDED, '导入文件超过 512 MiB'); files.set(name, data);
    }
    return {metadata: payload.metadata, files, metadataFile, base: metadataFile?.includes('/') ? metadataFile.slice(0,metadataFile.lastIndexOf('/')+1) : ''};
}

// Validate actual compressed pixels, chunk CRCs and row filters, not just the PNG signature.
function inspectPng(data) {
    assert(data.length >= 45 && data.subarray(0, 8).equals(Buffer.from('89504e470d0a1a0a', 'hex')), 'PNG 签名无效');
    let cursor = 8, header, ended = false, hasPalette = false, idatEnded = false;
    const compressed = [];
    while (cursor < data.length) {
        assert(cursor + 12 <= data.length, 'PNG 块头截断');
        const length = data.readUInt32BE(cursor), type = data.toString('ascii', cursor + 4, cursor + 8), end = cursor + 12 + length;
        assert(end <= data.length && /^[A-Za-z]{4}$/.test(type), 'PNG 块越界');
        assert(crc32(data.subarray(cursor + 4, end - 4)) === data.readUInt32BE(end - 4), 'PNG CRC 无效');
        const bytes = data.subarray(cursor + 8, end - 4);
        if (!header) {
            assert(type === 'IHDR' && length === 13, 'PNG 缺少 IHDR');
            header = {width: bytes.readUInt32BE(0), height: bytes.readUInt32BE(4), depth: bytes[8], color: bytes[9], interlace: bytes[12]};
            const allowed = {0: [1, 2, 4, 8, 16], 2: [8, 16], 3: [1, 2, 4, 8], 4: [8, 16], 6: [8, 16]};
            assert(header.width > 0 && header.width <= 16384 && header.height > 0 && header.height <= 16384 && allowed[header.color]?.includes(header.depth) && bytes[10] === 0 && bytes[11] === 0 && header.interlace <= 1, 'PNG 尺寸或编码无效');
        } else if (type === 'IDAT') {
            assert(!idatEnded && (header.color !== 3 || hasPalette), 'PNG IDAT 顺序无效'); compressed.push(bytes);
        } else {
            if (compressed.length) idatEnded = true;
            assert(type !== 'IHDR' && (!/^[A-Z]/.test(type) || ['PLTE', 'IEND'].includes(type)), 'PNG 未知关键块');
            if (type === 'PLTE') { assert(!hasPalette && !compressed.length && length > 0 && length <= 768 && length % 3 === 0, 'PNG 调色板无效'); hasPalette = true; }
            if (type === 'IEND') { assert(length === 0 && end === data.length && compressed.length > 0, 'PNG 结束块无效'); ended = true; }
        }
        cursor = end;
    }
    assert(ended, 'PNG 未完整结束');
    const channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[header.color];
    const passes = header.interlace ? [[0,0,8,8],[4,0,8,8],[0,4,4,8],[2,0,4,4],[0,2,2,4],[1,0,2,2],[0,1,1,2]] : [[0,0,1,1]];
    const rows = passes.map(([x,y,dx,dy]) => { const w = Math.max(0,Math.ceil((header.width-x)/dx)), h = Math.max(0,Math.ceil((header.height-y)/dy)); return {length: Math.ceil(w*channels*header.depth/8)+1, count: w ? h : 0}; });
    const expected = rows.reduce((sum,row) => sum+row.length*row.count,0);
    assert(expected <= MAX_EXPANDED, 'PNG 解码超过 512 MiB');
    const pixels = inflateSync(Buffer.concat(compressed), {maxOutputLength: expected});
    assert(pixels.length === expected, 'PNG 像素数据长度无效');
    let at = 0; for (const row of rows) for (let i=0;i<row.count;i++) { assert(pixels[at] <= 4, 'PNG 扫描行过滤器无效'); at += row.length; }
    return {...header, decodedBytes: expected};
}

function buildClip(metadata, files, base, importId) {
    assert(object(metadata) && object(metadata.meta) && Array.isArray(metadata.frames), 'FrameBaker 元数据结构无效');
    const meta = metadata.meta, frames = metadata.frames;
    assert(meta.app === 'FrameBaker' && ['sequence', 'spritesheet'].includes(meta.format), '需要 FrameBaker PNG 序列或精灵图导出');
    assert(finite(meta.fps) && meta.fps > 0 && meta.fps <= 240, 'FPS 必须在 0 到 240 之间');
    assert(frames.length > 0 && frames.length <= MAX_FILES && meta.count === frames.length, '帧数量无效');
    assert(integer(meta.cellWidth) && meta.cellWidth > 0 && meta.cellWidth <= 16384 && integer(meta.cellHeight) && meta.cellHeight > 0 && meta.cellHeight <= 16384, '统一画布尺寸无效');
    assert(finite(meta.originX) && finite(meta.originY) && meta.originX >= 0 && meta.originX <= meta.cellWidth && meta.originY >= 0 && meta.originY <= meta.cellHeight, '共同原点无效');
    const images = new Map(); let decoded = 0;
    for (const [name, bytes] of files) if (/\.png$/i.test(name)) { const info = inspectPng(bytes); decoded += info.decodedBytes; assert(decoded <= MAX_EXPANDED, 'PNG 总解码量超过 512 MiB'); images.set(name, info); }
    const output = frames.map(frame => {
        assert(object(frame) && finite(frame.duration) && frame.duration > 0, '帧 duration 必须是正数 tick');
        const file = safeName(frame.file), name = base + file, image = images.get(name);
        assert(image, `缺少 PNG：${name}`);
        assert(integer(frame.x) && integer(frame.y) && integer(frame.w) && integer(frame.h) && frame.w === meta.cellWidth && frame.h === meta.cellHeight, '帧区域与统一画布不一致');
        assert(frame.x + frame.w <= image.width && frame.y + frame.h <= image.height, '图集帧区域越界');
        if (meta.format === 'sequence') assert(frame.x === 0 && frame.y === 0 && frame.w === image.width && frame.h === image.height, '序列 PNG 尺寸不一致');
        else assert(meta.imageWidth === image.width && meta.imageHeight === image.height, '图集 PNG 尺寸不一致');
        const result = {asset: `image/imports/framebaker/${importId}/${name}`, width: frame.w, height: frame.h, pivotX: meta.originX, pivotY: meta.originY, durationTicks: frame.duration};
        if (meta.format === 'spritesheet') result.region = {x: frame.x, y: frame.y, width: frame.w, height: frame.h};
        return result;
    });
    return {fps: meta.fps, frames: output, loop: false, frameBaker: {app: 'FrameBaker', format: meta.format, originX: meta.originX, originY: meta.originY, cellWidth: meta.cellWidth, cellHeight: meta.cellHeight, ...(typeof meta.axisId === 'string' ? {axisId: meta.axisId.slice(0,1024)} : {}), ...(typeof meta.axisName === 'string' ? {axisName: meta.axisName.slice(0,1024)} : {})}};
}

async function importFrameBaker(request, assetsRoot) {
    const type = (request.headers['content-type'] || '').split(';')[0].trim().toLowerCase();
    assert(['application/zip', 'application/json'].includes(type), 'Content-Type 必须是 application/zip 或 application/json');
    const limit = type === 'application/zip' ? MAX_ARCHIVE : Math.ceil(MAX_EXPANDED * 4/3) + MAX_JSON;
    const length = Number(request.headers['content-length']);
    assert(!Number.isFinite(length) || length <= limit, '导入请求过大');
    const chunks = []; let size = 0;
    for await (const chunk of request) { size += chunk.length; assert(size <= limit, '导入请求过大'); chunks.push(chunk); }
    const body = Buffer.concat(chunks);
    let source;
    if (type === 'application/zip') {
        const files = unzip(body), metadataNames = [...files.keys()].filter(name => /\.frames\.json$/i.test(name));
        assert(metadataNames.length === 1, 'ZIP 必须包含且仅包含一个 .frames.json');
        const metadataFile = metadataNames[0];
        source = {metadata: JSON.parse(utf8.decode(files.get(metadataFile))), files, metadataFile, base: metadataFile.includes('/') ? metadataFile.slice(0,metadataFile.lastIndexOf('/')+1) : ''};
    } else source = parseFolder(JSON.parse(utf8.decode(body)));
    const importId = crypto.randomUUID();
    const clip = buildClip(source.metadata, source.files, source.base, importId);
    clip.frameBaker.metadataFile = source.metadataFile;
    const parent = path.join(assetsRoot, 'image', 'imports', 'framebaker'), destination = path.join(parent, importId);
    // Stage on the project volume outside served assets, then publish with one atomic rename.
    const stagingParent = path.join(path.dirname(assetsRoot), '.runtime');
    await fs.mkdir(stagingParent, {recursive: true});
    const staging = await fs.mkdtemp(path.join(stagingParent, 'framebaker-import-'));
    try {
        for (const [name, bytes] of source.files) if (/\.png$/i.test(name)) {
            const output = path.join(staging, name); await fs.mkdir(path.dirname(output), {recursive: true}); await fs.writeFile(output, bytes, {flag: 'wx'});
        }
        await fs.mkdir(parent, {recursive: true});
        await fs.rename(staging, destination);
    } finally { await fs.rm(staging, {recursive: true, force: true}); }
    return {ok: true, clip, importId, warnings: []};
}

module.exports = {importFrameBaker};
