'use strict';
const fs=require('node:fs/promises');
const path=require('node:path');
const crypto=require('node:crypto');
const missingRevision='missing';
const sha=text=>crypto.createHash('sha256').update(text).digest('hex');
function sorted(value) { if(Array.isArray(value))return value.map(sorted);if(value&&typeof value==='object')return Object.fromEntries(Object.keys(value).sort().map(k=>[k,sorted(value[k])]));return value; }
const serialize=value=>JSON.stringify(sorted(value),null,2)+'\n';
async function readTuning(root) {
  try { const bytes=await fs.readFile(path.join(root,'assets/data/tuning.json'));const data=JSON.parse(bytes.toString('utf8').replace(/^\uFEFF/,''));
    if(data.version!==1||!data.values||Array.isArray(data.values)||typeof data.values!=='object')throw Error('tuning.json 格式错误');
    return {values:data.values,revision:sha(bytes)};
  }catch(e) {if(e.code==='ENOENT')return {values:{},revision:missingRevision};throw e;}
}
async function atomicWrite(file,value,beforeRename) {
  await fs.mkdir(path.dirname(file),{recursive:true});const temp=file+'.'+process.pid+'.'+crypto.randomBytes(6).toString('hex')+'.tmp';
  try {const handle=await fs.open(temp,'wx');try{await handle.writeFile(serialize(value),'utf8');await handle.sync();}finally{await handle.close();}
    if(beforeRename)await beforeRename();await fs.rename(temp,file);
  }finally{await fs.unlink(temp).catch(e=>{if(e.code!=='ENOENT')throw e;});}
}
function presetName(value) {if(typeof value!=='string'||!value.trim()||value!==value.trim()||value.length>64||/[<>:"/\\|?*\x00-\x1f]/.test(value)||value==='.'||value==='..'||/[. ]$/.test(value)||/^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)/i.test(value))throw Object.assign(Error('方案名字不能包含路径字符或保留名称'),{status:400});return value;}
async function presetList(dir) {try{return (await fs.readdir(dir,{withFileTypes:true})).filter(x=>x.isFile()&&x.name.endsWith('.json')).map(x=>x.name.slice(0,-5)).sort();}catch(e){if(e.code==='ENOENT')return [];throw e;}}
module.exports={sha,serialize,readTuning,atomicWrite,presetName,presetList};
