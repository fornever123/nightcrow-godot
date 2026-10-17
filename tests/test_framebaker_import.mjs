import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import net from 'node:net';
import {spawn} from 'node:child_process';
import {deflateSync,deflateRawSync} from 'node:zlib';
import {randomBytes} from 'node:crypto';
const root=await fs.mkdtemp(path.join(os.tmpdir(),'framebaker-test-'));
const crc=data=>{let c=0xffffffff;for(const b of data){c^=b;for(let i=0;i<8;i++)c=(c>>>1)^((c&1)?0xedb88320:0);}return (c^0xffffffff)>>>0;};
const chunk=(type,data)=>{const b=Buffer.alloc(data.length+12);b.writeUInt32BE(data.length);b.write(type,4);data.copy(b,8);b.writeUInt32BE(crc(b.subarray(4,-4)),b.length-4);return b;};
function png(w=2,h=3){const ihdr=Buffer.alloc(13);ihdr.writeUInt32BE(w);ihdr.writeUInt32BE(h,4);ihdr[8]=8;ihdr[9]=6;return Buffer.concat([Buffer.from('89504e470d0a1a0a','hex'),chunk('IHDR',ihdr),chunk('IDAT',deflateSync(Buffer.alloc((w*4+1)*h))),chunk('IEND',Buffer.alloc(0))]);}
function zip(entries){let offset=0;const locals=[],centrals=[];for(const [name,data,declared] of entries){const n=Buffer.from(name),packed=deflateRawSync(data),c=crc(data),l=Buffer.alloc(30),d=Buffer.alloc(46);l.writeUInt32LE(0x04034b50);l.writeUInt16LE(20,4);l.writeUInt16LE(8,8);l.writeUInt32LE(c,14);l.writeUInt32LE(packed.length,18);l.writeUInt32LE(declared??data.length,22);l.writeUInt16LE(n.length,26);d.writeUInt32LE(0x02014b50);d.writeUInt16LE(20,6);d.writeUInt16LE(8,10);d.writeUInt32LE(c,16);d.writeUInt32LE(packed.length,20);d.writeUInt32LE(declared??data.length,24);d.writeUInt16LE(n.length,28);d.writeUInt32LE(offset,42);locals.push(l,n,packed);centrals.push(d,n);offset+=l.length+n.length+packed.length;}const cd=Buffer.concat(centrals),end=Buffer.alloc(22);end.writeUInt32LE(0x06054b50);end.writeUInt16LE(entries.length,8);end.writeUInt16LE(entries.length,10);end.writeUInt32LE(cd.length,12);end.writeUInt32LE(offset,16);return Buffer.concat([...locals,cd,end]);}
const meta=()=>({frames:[{file:'z.png',x:0,y:0,w:2,h:3,duration:2.5},{file:'a.png',x:0,y:0,w:2,h:3,duration:1}],meta:{fps:24,cellWidth:2,cellHeight:3,originX:0.25,originY:1.75,count:2,format:'sequence',app:'FrameBaker',axisName:'测试'}});
const image=png();
const files=()=>[{name:'a.png',contentBase64:image.toString('base64')},{name:'z.png',contentBase64:image.toString('base64')}];
const listener=net.createServer();await new Promise(r=>listener.listen(0,'127.0.0.1',r));const port=listener.address().port;await new Promise(r=>listener.close(r));
await fs.mkdir(path.join(root,'assets/data'),{recursive:true});await fs.writeFile(path.join(root,'assets/data/battle.json'),'original');
const child=spawn(process.execPath,[path.resolve(import.meta.dirname,'../tools/battle-editor/server.js'),'--root',root,'--port',String(port)],{stdio:['ignore','pipe','pipe']});
let output='';child.stdout.on('data',b=>output+=b);child.stderr.on('data',b=>output+=b);
const base=`http://127.0.0.1:${port}`;
let checks=0;
const check=(value,label)=>{assert.ok(value,label);checks++;};
async function post(value){const binary=Buffer.isBuffer(value);const r=await fetch(base+'/api/framebaker/import',{method:'POST',headers:{'Content-Type':binary?'application/zip':'application/json'},body:binary?value:JSON.stringify(value)});return {status:r.status,...await r.json()};}
async function ids(){return (await fs.readdir(path.join(root,'assets/image/imports/framebaker')).catch(()=>[])).sort();}
async function rejects(value,label){const before=await ids(),r=await post(value);check(r.status===400&&!r.ok,label+': '+JSON.stringify(r));assert.deepEqual(await ids(),before,label+' atomic');checks++;}
try{
 for(let i=0;i<80;i++){try{if((await fetch(base+'/api/health')).ok)break;}catch{}await new Promise(r=>setTimeout(r,50));}
 const folder=await post({metadata:meta(),files:files()});check(folder.ok,'folder import: '+JSON.stringify(folder));
 assert.deepEqual(folder.clip.frames.map(f=>[path.basename(f.asset),f.durationTicks,f.pivotX,f.pivotY]),[['z.png',2.5,.25,1.75],['a.png',1,.25,1.75]]);checks++;
 check(folder.clip.fps===24&&folder.clip.loop===false,'clip timing');
 check(image.equals(await fs.readFile(path.join(root,'assets',folder.clip.frames[0].asset))),'transparent PNG bytes preserved');
 const nestedFolder=await post({metadata:meta(),metadataFile:'bundle/action/test.frames.json',files:files().map(f=>({...f,name:'bundle/action/'+f.name}))});
 check(nestedFolder.ok,'nested folder import: '+JSON.stringify(nestedFolder));
 check(nestedFolder.clip.frames[0].asset.endsWith('/bundle/action/z.png')&&nestedFolder.clip.frameBaker.metadataFile==='bundle/action/test.frames.json','folder manifest directory resolves image references');
 await rejects({metadata:meta(),metadataFile:'../test.frames.json',files:files()},'folder manifest traversal');
 await rejects({metadata:meta(),metadataFile:'test.png',files:files()},'folder manifest extension');
 const archive=await post(zip([['bundle/test.frames.json',Buffer.from(JSON.stringify(meta()))],['bundle/a.png',image],['bundle/z.png',image]]));check(archive.ok,'ZIP nested import: '+JSON.stringify(archive));
 const ancillary=chunk('raNd',randomBytes(13*1024*1024));
 const largePng=Buffer.concat([image.subarray(0,-12),ancillary,image.subarray(-12)]);
 const largeArchive=zip([['test.frames.json',Buffer.from(JSON.stringify(meta()))],['a.png',largePng],['z.png',image]]);
 check(largeArchive.length>12*1024*1024,'fixture exceeds ordinary body limit');check((await post(largeArchive)).ok,'ZIP import has independent body limit');
 const sheet=meta();sheet.meta.format='spritesheet';sheet.meta.imageWidth=4;sheet.meta.imageHeight=3;sheet.frames.forEach((f,i)=>{f.file='sheet.png';f.x=i*2;});
 const atlas=await post({metadata:sheet,files:[{name:'sheet.png',contentBase64:png(4,3).toString('base64')}]});check(atlas.ok,'atlas import');assert.deepEqual(atlas.clip.frames[1].region,{x:2,y:0,width:2,height:3});checks++;
 await rejects(zip([['../bad.png',image],['test.frames.json',Buffer.from(JSON.stringify(meta()))]]),'ZipSlip');
 await rejects(zip([['test.frames.json',Buffer.from(JSON.stringify(meta()))],['TEST.frames.json',Buffer.from('{}')]]),'duplicate metadata');
 await rejects(zip([['test.frames.json',Buffer.from(JSON.stringify(meta()))],['a.png',image],['A.png',image]]),'case collision');
 await rejects(zip([['bomb.png',image,513*1024*1024]]),'declared ZIP bomb');
 await rejects(zip([['bomb.png',Buffer.alloc(1024*1024),1]]),'actual deflate expansion exceeds declared size');
 await rejects(zip(Array.from({length:4097},(_,i)=>[`${i}.png`,image])),'ZIP file count limit');
 const badCrc=zip([['test.frames.json',Buffer.from(JSON.stringify(meta()))],['a.png',image],['z.png',image]]);badCrc[14]^=1;await rejects(badCrc,'ZIP local header disagreement');
 const link=zip([['test.frames.json',Buffer.from(JSON.stringify(meta()))],['a.png',image],['z.png',image]]);let central=link.readUInt32LE(link.length-6);central+=46+Buffer.byteLength('test.frames.json');link.writeUInt32LE(0xa1ff0000,central+38);await rejects(link,'ZIP symbolic link');
 await rejects(zip([['test.frames.json',Buffer.from(JSON.stringify(meta()))],['a.png',image],['z.png',image],['link.png',image]]).subarray(0,40),'truncated ZIP');
 const bad=meta();bad.frames[0].duration='NaN';await rejects({metadata:bad,files:files()},'NaN ticks');
 bad.frames[0].duration=0;await rejects({metadata:bad,files:files()},'zero ticks');
 await rejects({metadata:meta(),files:files().slice(0,1)},'missing PNG');
 await rejects({metadata:meta(),files:files().map(f=>({...f,contentBase64:Buffer.from('not PNG').toString('base64')}))},'fake PNG');
 const corrupt=Buffer.from(image);corrupt[corrupt.length-5]^=1;await rejects({metadata:meta(),files:files().map(f=>({...f,contentBase64:corrupt.toString('base64')}))},'corrupt PNG');
 const oob=structuredClone(sheet);oob.frames[1].x=4;await rejects({metadata:oob,files:[{name:'sheet.png',contentBase64:png(4,3).toString('base64')}]},'atlas overflow');
 await rejects({metadata:meta(),files:[...files(),{name:'other.frames.json',contentBase64:Buffer.from('{}').toString('base64')}]},'folder extra metadata');
 await rejects({metadata:meta(),files:[...files(),{name:'../outside.png',contentBase64:image.toString('base64')}]},'folder traversal');
 const mismatch=meta();mismatch.meta.cellWidth=5;await rejects({metadata:mismatch,files:files()},'inconsistent canvas');
 const huge=meta();huge.frames=Array(4097).fill(huge.frames[0]);huge.meta.count=4097;await rejects({metadata:huge,files:files()},'frame limit');
 check(await fs.readFile(path.join(root,'assets/data/battle.json'),'utf8')==='original','configuration untouched');
 const validationConfig={characters:[{id:'player',sprite:{animations:{idle:{fps:240,frames:[{...folder.clip.frames[0],width:16384}]}}}},{id:'dummy'}]};
 async function validate(config){const r=await fetch(base+'/api/validate',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(config)});return (await r.json()).validation.errors;}
 check(!(await validate(validationConfig)).some(e=>e.includes('播放帧率')||e.includes('idle width')),'FrameBaker dimensions and FPS survive configuration validation');
 validationConfig.characters[0].sprite.animations.idle.frames[0].durationTicks=0;
 check((await validate(validationConfig)).some(e=>e.includes('durationTicks')),'configuration rejects nonpositive imported ticks');
 const validatedClip=validationConfig.characters[0].sprite.animations.idle;
 validatedClip.frames[0].durationTicks=2.5;validatedClip.effectsBaked='true';
 check((await validate(validationConfig)).some(e=>e.includes('effectsBaked')),'configuration rejects nonboolean baked marker');
 validatedClip.effectsBaked=false;validatedClip.overlayEffect='missing';
 check((await validate(validationConfig)).some(e=>e.includes('overlayEffect')),'configuration rejects missing overlay effect');
 validatedClip.effectsBaked=true;
 check((await validate(validationConfig)).some(e=>e.includes('overlayEffect')),'configuration rejects dangling overlay even when baked');
 validatedClip.overlayEffect='toString';
 check((await validate(validationConfig)).some(e=>e.includes('overlayEffect')),'configuration rejects inherited overlay property');
 validatedClip.overlayEffect=123;
 check((await validate(validationConfig)).some(e=>e.includes('overlayEffect')),'configuration rejects nonstring overlay reference');
 validationConfig.characters[0].sprite.effects={slash:{fps:24,frames:folder.clip.frames}};validatedClip.overlayEffect='slash';
 check(!(await validate(validationConfig)).some(e=>e.includes('overlayEffect')||e.includes('effectsBaked')),'configuration accepts existing overlay and boolean marker');
 validatedClip.overlayEffect='';validatedClip.effectsBaked=false;
 check(!(await validate(validationConfig)).some(e=>e.includes('overlayEffect')||e.includes('effectsBaked')),'configuration accepts disabled overlay');
 console.log(`FRAMEBAKER_IMPORT_TESTS: ${checks} checks / 0 failures`);
}finally{child.kill();await new Promise(r=>child.once('exit',r));const resolved=path.resolve(root);assert.ok(resolved.startsWith(path.resolve(os.tmpdir())+path.sep));await fs.rm(resolved,{recursive:true,force:true});}
