'use strict';
const http=require('node:http');
const fs=require('node:fs/promises');
const path=require('node:path');
const {createModel,displayValue,moveFrames}=require('./lib/model');
const {validateValues}=require('./lib/validation');
const {sha,serialize,readTuning,atomicWrite,presetName,presetList}=require('./lib/storage');
const {gameManager}=require('./lib/game');
const {sceneManager}=require('./lib/scene');
const toolDir=__dirname;
function options(args) {
  const result={root:path.resolve(toolDir,'../..'),port:4330};
  for(let i=0;i<args.length;i+=2) {const flag=args[i];if(!['--root','--port','--godot'].includes(flag)||args[i+1]===undefined)throw Error('参数：--root <目录> --port <端口> --godot <程序>');result[flag.slice(2)]=args[i+1];}
  result.root=path.resolve(result.root);result.port=Number(result.port);
  if(!Number.isInteger(result.port)||result.port<0||result.port>65535)throw Error('端口无效');
  result.godot=path.resolve(result.godot||path.join(result.root,'engine/Godot_v4.7.2-stable_win64_console.exe'));return result;
}
async function start(opts) {
  const scene=sceneManager(opts.root),game=gameManager(opts.root,opts.godot),presetsDir=path.join(opts.root,'tools/modifier/presets');
  let queue=Promise.resolve();
  const serial=fn=>{const next=queue.then(fn);queue=next.catch(()=>{});return next;};
  async function model() {const [catalog,battle,encounters]=await Promise.all([fs.readFile(path.join(toolDir,'catalog.json'),'utf8'),fs.readFile(path.join(opts.root,'assets/data/battle.json'),'utf8'),fs.readFile(path.join(opts.root,'assets/data/encounters.json'),'utf8')]);
    const docs={battle:JSON.parse(battle.replace(/^\uFEFF/,'')),encounters:JSON.parse(encounters.replace(/^\uFEFF/,'')),...(await scene.documents())};return {data:createModel(JSON.parse(catalog.replace(/^\uFEFF/,'')),docs),docs};}
  async function body(req,limit=4*1024*1024) {let bytes=0,chunks=[];for await(const chunk of req){bytes+=chunk.length;if(bytes>limit)throw Object.assign(Error('请求内容太大'),{status:413});chunks.push(chunk);}try{return JSON.parse(Buffer.concat(chunks).toString('utf8'));}catch{throw Object.assign(Error('请求不是合法 JSON'),{status:400});}}
  const json=(res,status,value)=>{res.writeHead(status,{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'});res.end(JSON.stringify(value));};
  const server=http.createServer(async(req,res)=>{
    try {
      const host=req.headers.host;
      if(!/^127\.0\.0\.1:\d+$/.test(host||'')&&!/^localhost:\d+$/.test(host||''))throw Object.assign(Error('仅允许本机访问'),{status:403});
      if(req.headers.origin&&!['http://'+host].includes(req.headers.origin))throw Object.assign(Error('不允许跨站请求'),{status:403});
      const url=new URL(req.url,'http://'+host),method=req.method;
      if(method==='GET'&&url.pathname==='/api/health')return json(res,200,{projectRoot:opts.root,service:'nightcrow-modifier',version:3});
      if(method==='GET'&&url.pathname==='/api/state') {const [{data},tuning,presets]=await Promise.all([model(),readTuning(opts.root),presetList(presetsDir)]);const items=data.items.map(item=>({...item,currentValue:tuning.values[item.path]??item.defaultValue,defaultDisplayValue:displayValue(data,{},item),currentDisplayValue:displayValue(data,tuning.values,item)}));const moves=data.moves.map(move=>({...move,currentFrames:moveFrames(data,tuning.values,move.id)}));return json(res,200,{projectRoot:opts.root,...data,items,moves,...tuning,presets,game:game.status(),scene:await scene.info()});}
      if(method==='GET'&&url.pathname==='/scene-image') {const image=await scene.readImage(url.searchParams.get('path'));res.writeHead(200,{'Content-Type':'image/png','Cache-Control':'max-age=3600','X-Content-Type-Options':'nosniff'});return res.end(image);}
      if(method==='POST'&&url.pathname==='/api/scene/bake') {const input=await body(req);return await serial(async()=>json(res,200,{art:await scene.bake(input.plan)}));}
      if(method==='POST'&&url.pathname==='/api/scene/import') {const input=await body(req,96*1024*1024);return await serial(async()=>json(res,200,await scene.importImage(input)));}
      if(method==='POST'&&url.pathname==='/api/apply') {const input=await body(req);return await serial(async()=>{
        const {data,docs}=await model();validateValues(data,input.values,docs.encounters.kinds);
        const check=async()=>{if((await readTuning(opts.root)).revision!==input.baseRevision)throw Object.assign(Error('文件被别处改过'),{status:409});};await check();
        const output={version:1,values:input.values};await atomicWrite(path.join(opts.root,'assets/data/tuning.json'),output,check);await scene.prune(presetsDir).catch(()=>{});json(res,200,{revision:sha(serialize(output))});
      });}
      if(url.pathname==='/api/presets') {
        if(method==='GET') {if(url.searchParams.has('name')) {const name=presetName(url.searchParams.get('name'));const saved=JSON.parse(await fs.readFile(path.join(presetsDir,name+'.json'),'utf8'));const {data,docs}=await model();validateValues(data,saved.values,docs.encounters.kinds);return json(res,200,{name,values:saved.values});}return json(res,200,{presets:await presetList(presetsDir)});}
        if(method==='POST'||method==='DELETE') {const input=await body(req);return await serial(async()=>{const name=presetName(input.name),file=path.join(presetsDir,name+'.json');if(method==='POST') {const {data,docs}=await model();validateValues(data,input.values,docs.encounters.kinds);await atomicWrite(file,{version:1,values:input.values});}else await fs.unlink(file);json(res,200,{presets:await presetList(presetsDir)});});}
      }
      if(method==='POST'&&url.pathname==='/api/game/launch') {const input=await body(req);return await serial(async()=>json(res,200,await game.launch(input.scene)));}
      if(method==='POST'&&url.pathname==='/api/game/stop')return await serial(async()=>json(res,200,await game.stop()));
      const staticFiles={'/':['public/index.html','text/html'],'/app.js':['public/app.js','text/javascript'],'/style.css':['public/style.css','text/css'],'/model.js':['lib/model.js','text/javascript'],'/scene.js':['public/scene.js','text/javascript']};
      if(method==='GET'&&Object.hasOwn(staticFiles,url.pathname)) {const [file,type]=staticFiles[url.pathname];res.writeHead(200,{'Content-Type':type+'; charset=utf-8','Cache-Control':'no-cache','X-Content-Type-Options':'nosniff','Content-Security-Policy':"default-src 'self'; style-src 'self'; script-src 'self'; img-src 'self' data:; object-src 'none'; base-uri 'none'; frame-ancestors 'none'"});return res.end(await fs.readFile(path.join(toolDir,file)));}
      json(res,404,{error:'没有这个接口或文件'});
    }catch(e) {if(!res.headersSent)json(res,e.status||(e.code==='ENOENT'?404:500),{error:e.message,...(e.code?{code:e.code}:{})});else res.end();}
  });
  server.requestTimeout=15000;
  await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(opts.port,'127.0.0.1',resolve);});
  const shutdown=async()=>{await game.stop().catch(e=>console.error(e.message));server.close(()=>process.exit(0));setTimeout(()=>process.exit(1),3000).unref();};
  process.once('SIGTERM',shutdown);process.once('SIGINT',shutdown);
  console.log('夜鸦修改器 '+JSON.stringify({projectRoot:opts.root,port:server.address().port}));
  return server;
}
if(require.main===module)start(options(process.argv.slice(2))).catch(e=>{console.error(e.message);process.exitCode=1;});
module.exports={start,options};
