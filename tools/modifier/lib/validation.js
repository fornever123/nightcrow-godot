'use strict';
function bad(message) {throw Object.assign(Error(message),{status:400});}
function validateValues(model,values,kinds) {
  if(!values||typeof values!=='object'||Array.isArray(values))bad('values 必须是参数对象');
  for(const [key,value] of Object.entries(values)) {
    if(!Object.hasOwn(model.defaults,key))bad('不允许的参数路径：'+key);
    if(key.startsWith('layout/')||key.startsWith('scene/')) {if(!validateScene(key,value,model.defaults[key]))continue;}
    if(key==='encounters/waves') {validateWaves(value,kinds,model.defaults[key].length);continue;}
    const def=model.defaults[key];
    if(typeof def==='boolean') {if(typeof value!=='boolean')bad(key+' 必须是开关值');}
    else if(typeof value!=='number'||!Number.isFinite(value))bad(key+' 必须是有限数字');
  }
  return values;
}
const num=v=>typeof v==='number'&&Number.isFinite(v);
// 每条末尾可带选项：off 不生效，solid/pass 挡不挡，bottom 实心到哪儿。
const optsOk=(o,y)=>o===undefined||(o&&typeof o==='object'&&!Array.isArray(o)&&Object.entries(o).every(([k,v])=>['off','solid','pass'].includes(k)?typeof v==='boolean':k==='bottom'&&num(v)&&v>y));
const barOk=r=>(r.length===4||r.length===5)&&num(r[0])&&num(r[1])&&num(r[2])&&typeof r[3]==='string'&&r[0]<r[1]&&optsOk(r[4],r[2]);
const rows={
  platforms:barOk,
  blocks:barOk,
  slopes:r=>(r.length===5||r.length===6)&&num(r[0])&&num(r[1])&&num(r[2])&&num(r[3])&&typeof r[4]==='string'&&r[0]<r[2]&&optsOk(r[5],-Infinity),
  spawns:r=>r.length===2&&num(r[0])&&num(r[1]),
  lamps:r=>r.length>=3&&num(r[0])&&num(r[1])&&typeof r[2]==='string'&&(r[3]===undefined||num(r[3])),
  foreground:r=>r.length===2&&num(r[0])&&typeof r[1]==='string',
};
const resPath=v=>typeof v==='string'&&/^res:\/\/assets\/image\/rain_street\/[^.]+.*\.png$/i.test(v)&&!v.includes('..');
// 返回 true 表示还要按普通数字项继续检查。
function validateScene(key,value,def) {
  const field=key.split('/').pop();
  if(key.startsWith('scene/plan/')) {
    if(!value||!Array.isArray(value.items)||!num(value.x0)||!num(value.x1)||value.x0>=value.x1)bad(key+' 方案格式不对');
    for(const it of value.items)if(!it||typeof it.piece!=='string'||!num(it.x)||!num(it.y)||!num(it.z)||typeof it.mirror!=='boolean')bad(key+' 方案里有一件格式不对');
    return false;
  }
  if(key.startsWith('layout/sections/')) {
    if(field==='art') {if(!value||!resPath(value.near)||!num(value.x0)||!num(value.y0)||!num(value.width))bad(key+' 成图格式不对');return false;}
    if(!Array.isArray(value)||value.some(r=>!Array.isArray(r)||!rows[field](r)))bad(key+' 格式不对');
    return false;
  }
  if(field==='tex') {if(!resPath(value))bad(key+' 图片路径不对');return false;}
  if(field==='depth') {if(!Array.isArray(value)||value.some(r=>!r||!resPath(r.tex)||!num(r.scroll)||!num(r.bottom)))bad(key+' 背街层格式不对');return false;}
  return typeof def!=='object';
}
function validateWaves(waves,kinds,count) {
  if(!Array.isArray(waves)||waves.length!==count)bad('波次必须保留 '+count+' 处封印');
  for(const seal of waves) {
    if(!Array.isArray(seal))bad('封印波次必须是列表');
    for(const wave of seal) {
      if(!wave||typeof wave!=='object'||Array.isArray(wave))bad('波次必须是对象');
      if(Object.keys(wave).some(k=>!['label','spawns','reinforce','reinforce_at','max_attackers'].includes(k)))bad('波次包含未知字段');
      if(typeof wave.label!=='string'||!wave.label.trim())bad('波次名称不能为空');
      if(!Array.isArray(wave.spawns)||!wave.spawns.length)bad('每波至少需要一只敌人');
      for(const list of [wave.spawns,wave.reinforce??[]]) {if(!Array.isArray(list)||list.some(k=>typeof k!=='string'||!Object.hasOwn(kinds,k)))bad('波次包含未知敌人');}
      if(!Number.isInteger(wave.max_attackers)||wave.max_attackers<=0)bad('同时出刀数量必须是正整数');
      if(wave.reinforce_at!==undefined&&(!Number.isInteger(wave.reinforce_at)||wave.reinforce_at<=0))bad('增援阈值必须是正整数');
      if(wave.reinforce?.length&&wave.reinforce_at===undefined)bad('有增援时需要填写增援阈值');
    }
  }
}
module.exports={validateValues};
