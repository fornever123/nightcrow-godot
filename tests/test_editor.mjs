import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
const root=path.resolve(import.meta.dirname,'..'),base=process.env.EDITOR_URL||'http://127.0.0.1:4329';
let count=0;
const check=(ok,name)=>{assert.ok(ok,name);count++;};
async function request(route,value) {const r=await fetch(base+route,value===undefined?{}:{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(value)});return {status:r.status,...await r.json()};}
const original=(await request('/api/config')).config;
const project=(await request('/api/editor-project')).project;
let uploaded='';
try {
  check((await request('/api/health')).engine==='Godot','Godot 服务');
  check((await request('/api/validate',original)).validation.ok,'基础配置有效');
  const invalid=structuredClone(original);invalid.moves[0].activeFrameEnd=999;
  check(!(await request('/api/validate',invalid)).validation.ok,'拒绝越界动作帧');
  const badAudio=structuredClone(original);badAudio.audio.events.blade_hit='audio/missing.wav';
  check(!(await request('/api/validate',badAudio)).validation.ok,'拒绝缺失战斗音效');
  const badVolume=structuredClone(original);badVolume.audio.sfxVolume=2;
  check(!(await request('/api/validate',badVolume)).validation.ok,'拒绝无效音量');
  const noFeedback=structuredClone(original);noFeedback.feedback.hitstopMultiplier=0;noFeedback.feedback.shakeMultiplier=0;
  check((await request('/api/validate',noFeedback)).validation.ok,'允许关闭顿帧和震屏');
  const badSquash=structuredClone(original);badSquash.moves[0].squashY=-1;
  check(!(await request('/api/validate',badSquash)).validation.ok,'拒绝反转角色受击形变');
  const badSpeed=structuredClone(original);badSpeed.characters[0].sprite.displayScale=0;
  check((await request('/api/config',badSpeed)).status===400,'拒绝无效角色大小');
  const source=original.characters[0].sprite.animations.idle.frames[0].asset;
  const bytes=await fs.readFile(path.join(root,'assets',source));
  const upload=await request('/api/upload',{category:'image',filename:'imports/api-test-'+Date.now()+'.png',contentBase64:bytes.toString('base64')});
  check(upload.ok,'导入 PNG 原图');uploaded=upload.path;
  check(bytes.equals(Buffer.from(await (await fetch(base+'/project-assets/'+uploaded)).arrayBuffer())),'导入不改变图片像素或压缩内容');
  check((await request('/api/asset/delete',{path:source})).status===400,'保护使用中的动作素材');
  const changed=structuredClone(original);changed.moves[0].animationSpeed=1.25;
  const saved=await request('/api/project/save',{config:changed,project});
  check(saved.ok&&saved.backup,'保存及自动备份');
  check((await request('/api/config')).config.moves[0].animationSpeed===1.25,'新配置写入正式工程');
  const start=await request('/api/game/start',{});
  check(start.ok&&start.status.process_alive,'修改器直接启动 Godot');
  let marker;
  for(let n=0;n<25;n++){await new Promise(r=>setTimeout(r,100));try{marker=JSON.parse(await fs.readFile(path.join(root,'.runtime/game.json'),'utf8'));if(marker.moveFrames.light_1===30)break;}catch{}}
  check(marker?.moveFrames.light_1===30,'Godot 实际读取了修改后的动作速度');
  const reset=await request('/api/project/save',{config:original,project});
  check(reset.ok,'恢复测试前配置');
  for(let n=0;n<25;n++){await new Promise(r=>setTimeout(r,100));try{marker=JSON.parse(await fs.readFile(path.join(root,'.runtime/game.json'),'utf8'));if(marker.moveFrames.light_1===37)break;}catch{}}
  check(marker?.moveFrames.light_1===37,'保存后 Godot 自动应用，不需重新启动');
  const removed=await request('/api/asset/delete',{path:uploaded});
  check(removed.ok,'不用的测试素材进入回收站');uploaded='';
  const status=await request('/api/game/status');
  check(status.status.process_alive,'原窗口保持运行');
  console.log(`EDITOR_TESTS: ${count} checks / 0 failures`);
} finally {
  await request('/api/project/save',{config:original,project});
  if(uploaded) await request('/api/asset/delete',{path:uploaded});
}
