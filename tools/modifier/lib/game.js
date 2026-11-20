'use strict';
const fs=require('node:fs');
const path=require('node:path');
const {spawn}=require('node:child_process');
const scenes={rain:'res://scenes/rain_trial.tscn',training:'res://scenes/training.tscn'};
function gameManager(root,godot) {
  let child=null,scene=null,lastError=null;
  const status=()=>({running:!!child&&child.exitCode===null&&child.signalCode===null,scene:child?scene:null,pid:child?.pid??null,error:lastError});
  async function stop() {
    const old=child;if(!old)return status();
    const exited=new Promise(resolve=>old.once('exit',resolve));
    if(old.exitCode===null&&old.signalCode===null) {
      if(process.platform==='win32')await new Promise((resolve,reject)=>{const killer=spawn('taskkill.exe',['/PID',String(old.pid),'/T','/F'],{windowsHide:true,stdio:['ignore','pipe','pipe']});let detail='';killer.stdout.on('data',chunk=>{detail+=chunk;});killer.stderr.on('data',chunk=>{detail+=chunk;});killer.once('error',reject);killer.once('exit',code=>{if(code!==0&&old.exitCode===null)reject(Object.assign(Error('无法结束修改器启动的游戏进程树：'+detail.trim()),{code:'GAME_STOP_FAILED'}));else resolve();});});
      else old.kill('SIGTERM');
      await Promise.race([exited,new Promise((_,reject)=>{const timer=setTimeout(()=>reject(Error('等待游戏结束超时')),5000);timer.unref();})]);
    }
    if(child===old){child=null;scene=null;}return status();
  }
  async function launch(next) {
    if(!Object.hasOwn(scenes,next))throw Object.assign(Error('请选择雨街或训练场'),{status:400});
    if(status().running&&scene===next)return status();
    await stop();lastError=null;
    fs.mkdirSync(path.join(root,'.runtime'),{recursive:true});const fd=fs.openSync(path.join(root,'.runtime/modifier-game.log'),'a');
    const args=['--path',root,scenes[next]];let proc;
    try {
      if(/\.(cmd|bat)$/i.test(godot)&&process.platform==='win32') {
        if(/["\r\n%]/.test(godot+root))throw Error('批处理游戏路径包含不支持的字符');
        proc=spawn(process.env.ComSpec||'cmd.exe',['/d','/s','/c','""'+godot+'" --path "'+root+'" "'+scenes[next]+'""'],{windowsHide:true,windowsVerbatimArguments:true,stdio:['ignore',fd,fd],cwd:root});
      } else if(/\.(?:c|m)?js$/i.test(godot))proc=spawn(process.execPath,[godot,...args],{windowsHide:true,stdio:['ignore',fd,fd],cwd:root});
      else proc=spawn(godot,args,{windowsHide:true,stdio:['ignore',fd,fd],cwd:root});
      child=proc;scene=next;
      proc.once('exit',()=>{if(child===proc){child=null;scene=null;}});
      await new Promise((resolve,reject)=>{proc.once('spawn',resolve);proc.once('error',e=>{lastError=e.message;if(child===proc){child=null;scene=null;}reject(e);});});
      return status();
    }finally{fs.closeSync(fd);}
  }
  return {status,launch,stop};
}
module.exports={gameManager};
