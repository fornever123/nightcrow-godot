'use strict';
(() => {
  const M = window.Modifier;
  const $ = (q) => document.querySelector(q);
  const clone = (v) => JSON.parse(JSON.stringify(v));
  const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);
  const esc = (v) => String(v ?? '').replace(/[&<>"']/g, (c) => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const fmt = (v) => typeof v === 'boolean' ? (v ? '开启' : '关闭') : typeof v === 'number' ? String(Math.round(v * 10000) / 10000) : Array.isArray(v) ? '自定义波次' : String(v ?? '—');
  let state, values = {}, applied = {}, pageId = 'player', entityId = null, query = '', history = [], future = [], busy = false, allConfirm = false, deleteConfirm = null, noticeTimer, gesture = null, baseRevision, draftKey;
  const pages = () => state.catalog.pages;
  const page = (id = pageId) => pages().find(p => p.id === id);
  const moves = () => Array.isArray(state.moves) ? state.moves : Object.values(state.moves);
  const move = (id) => moves().find(m => m.id === id);
  const entity = (item) => item.entityId ? (page(item.pageId)?.moves || page(item.pageId)?.kinds || []).find(e => e.id === item.entityId) : null;
  const disp = (item, set = values) => M.displayValue(state, set, item);
  const pendingPaths = () => [...new Set([...Object.keys(applied), ...Object.keys(values)])].filter(k => !equal(applied[k], values[k]));
  const itemChanged = (item, set = values) => !equal(disp(item, set), disp(item, {}));
  const isPending = (item) => !equal(disp(item, applied), disp(item, values));
  const itemLabel = (item) => (entity(item) ? entity(item).label + ' · ' : '') + item.label;
  const rowId = (path) => 'item-' + path.replace(/[^a-zA-Z0-9_-]/g, '-');
  function notify(message, error = false) {
    clearTimeout(noticeTimer); const el = $('#notice'); el.textContent = message; el.className = 'notice' + (error ? ' error' : ''); el.hidden = false;
    noticeTimer = setTimeout(() => { el.hidden = true; }, error ? 10000 : 5000);
  }
  async function api(url, method = 'GET', body) {
    const response = await fetch(url, { method, headers: body ? {'Content-Type':'application/json'} : undefined, body: body ? JSON.stringify(body) : undefined });
    let data; try { data = await response.json(); } catch { throw new Error('服务返回了无法读取的内容'); }
    if (!response.ok) { const error = new Error(data.error || data.message || '操作失败'); error.status = response.status; throw error; }
    return data;
  }
  function saveDraft() {
    try { if (pendingPaths().length) localStorage.setItem(draftKey, JSON.stringify({values, applied, baseRevision})); else localStorage.removeItem(draftKey); }
    catch { notify('浏览器无法保存草稿，请在关闭页面前应用改动。', true); }
  }
  function commit(next, remember = true) {
    if (equal(next, values)) return;
    if (remember) { history.push(clone(values)); if (history.length > 150) history.shift(); future = []; }
    values = clone(next); allConfirm = false; saveDraft(); renderSide(); updateTop(); window.SceneEditor.refresh();
  }
  function edit(item, value, remember = true) {
    try { commit(M.editValues(state, values, item, value), remember); syncParameters(); renderDynamic(); }
    catch (error) { notify(error.message, true); syncParameters(); }
  }
  function restore(item) { commit(M.resetValue(state, values, item)); render(); }
  function finishGesture(){if(gesture&&!equal(gesture,values)){history.push(gesture);future=[];}gesture=null;}
  function undo() { finishGesture(); if (!history.length) return; future.push(clone(values)); values = history.pop(); saveDraft(); render(); }
  function redo() { finishGesture(); if (!future.length) return; history.push(clone(values)); values = future.pop(); saveDraft(); render(); }
  function updateTop() {
    // 按用户看到的项数算：改一次帧数底层写四个速度、联动招式也写一份，但都只算一项。
    const pendingItems = state.items.filter(isPending).length + (equal(applied['encounters/waves'], values['encounters/waves']) ? 0 : 1);
    const pendingTotal = pendingItems + window.SceneEditor.pendingCount(applied);
    $('#pending-count').textContent = pendingTotal + ' 项待应用';
    $('#pending-count').classList.toggle('has-pending', pendingTotal > 0);
    const game = state.game || {}; const running = game.running || game.status === 'running';
    $('#game-status').textContent = running ? '游戏运行中 · ' + (game.scene === 'training' ? '训练场' : '雨街') : '游戏未运行';
    $('#stop-game').disabled = busy || !running;
    ['#apply-rain','#apply-training','#apply-only'].forEach(q => $(q).disabled = busy);
    $('#undo').disabled = !history.length; $('#redo').disabled = !future.length;
  }
  function renderNavigation() {
    $('#navigation').innerHTML = pages().map(p => '<button data-page="' + esc(p.id) + '" class="' + (pageId === p.id && !query ? 'active' : '') + '">' + esc(p.title) + '</button>').join('') + '<div class="nav-divider"></div><button data-page="presets" class="' + (pageId === 'presets' && !query ? 'active' : '') + '">方案</button>';
  }
  function renderSide() {
    const entries = state.items.filter(item => itemChanged(item) || itemChanged(item, applied) || isPending(item));
    let html = '';
    for (const p of pages()) {
      const rows = entries.filter(item => item.pageId === p.id);
      const wave = p.template === 'waves' && (Object.hasOwn(values,'encounters/waves') || Object.hasOwn(applied,'encounters/waves'));
      if (!rows.length && !wave) continue;
      html += '<div class="change-group"><h3>' + esc(p.title) + '</h3>';
      html += rows.map(item => '<div class="change-row"><button class="change-jump" data-jump="' + esc(item.path) + '">' + esc(itemLabel(item)) + '<span class="change-values">' + esc(fmt(disp(item, {}))) + ' → ' + esc(fmt(disp(item))) + (item.unit ? ' ' + esc(item.unit) : '') + '</span><span class="change-badge ' + (isPending(item) ? 'staged' : '') + '">' + (isPending(item) ? '还没应用' : '已在游戏里') + '</span>' + (isPending(item) && itemChanged(item, applied) ? '<span class="change-values">已应用：' + esc(fmt(disp(item, applied))) + '</span>' : '') + '</button><button class="change-remove" data-reset="' + esc(item.path) + '" aria-label="恢复' + esc(itemLabel(item)) + '">×</button></div>').join('');
      if (wave) html += '<div class="change-row"><button class="change-jump" data-page="waves">波次安排<span class="change-values">默认波次 → ' + (Object.hasOwn(values,'encounters/waves') ? '自定义波次' : '默认波次') + '</span><span class="change-badge ' + (!equal(values['encounters/waves'], applied['encounters/waves']) ? 'staged' : '') + '">' + (!equal(values['encounters/waves'], applied['encounters/waves']) ? '还没应用' : '已在游戏里') + '</span></button><button class="change-remove" data-reset-waves aria-label="恢复默认波次">×</button></div>';
      html += '</div>';
    }
    html += window.SceneEditor.changesHtml(applied);
    $('#changes').innerHTML = html || '<p class="empty">现在是默认数值。改过的项会列在这里。</p>';
    $('#reset-all').innerHTML = allConfirm ? '<p class="confirm-reset">恢复所有默认值？应用后生效。</p><button data-confirm-reset class="danger">确认全部恢复默认</button><button data-cancel-reset>取消</button>' : '<button data-reset-all class="subtle" ' + (!Object.keys(values).length ? 'disabled' : '') + '>全部恢复默认</button>';
  }
  function heading(title, hint, extra = '') { return '<div class="page-heading"><div><h2>' + esc(title) + '</h2><p>' + esc(hint || '') + '</p></div>' + extra + '</div>'; }
  function phaseEditable(item) {
    if (!item.phase) return true;
    const timing = move(item.entityId)?.timing;
    if (M.phaseEditable) return M.phaseEditable(timing, item.phase);
    const r = timing.raw; return ({startup:r.start, active:r.end-r.start, recovery:r.chain-r.end, tail:r.duration-r.chain})[item.phase] > 0;
  }
  function row(item) {
    const current = disp(item), changed = itemChanged(item), disabled = !phaseEditable(item);
    const info = '<div><label for="' + rowId(item.path) + '-number">' + esc(item.label) + '</label><p class="help">' + esc(item.help) + '<span class="default-line">默认 ' + esc(fmt(disp(item, {}))) + (item.unit ? ' ' + esc(item.unit) : '') + '</span></p></div>';
    let controls;
    if (disabled) controls = '<span class="disabled-phase">这招没有这一段</span>';
    else if (item.type === 'bool') controls = '<label class="switch"><input id="' + rowId(item.path) + '-number" type="checkbox" data-item="' + esc(item.path) + '" ' + (current ? 'checked' : '') + '><span>' + (current ? '开启' : '关闭') + '</span></label>';
    else controls = '<input type="range" data-def="' + Math.max(0, Math.min(100, (Number(disp(item, {})) - item.min) / (item.max - item.min) * 100)) + '%" aria-label="' + esc(item.label) + '滑块" data-item="' + esc(item.path) + '" min="' + item.min + '" max="' + item.max + '" step="' + (item.step || 'any') + '" value="' + current + '"><input id="' + rowId(item.path) + '-number" type="number" data-item="' + esc(item.path) + '" step="' + (item.step || 'any') + '" value="' + current + '"><span class="unit">' + esc(item.unit || '') + '</span>';
    return '<div id="' + rowId(item.path) + '" class="parameter' + (changed ? ' modified' : '') + '" data-row="' + esc(item.path) + '">' + info + controls + '<div class="row-meta"><span class="range-warning">' + (!disabled && typeof current === 'number' && (current < item.min || current > item.max) ? '超出常用范围' : '') + '</span><button data-reset="' + esc(item.path) + '" class="restore" ' + (!changed ? 'hidden' : '') + '>恢复</button></div></div>';
  }
  function sections(p, selected) {
    return (p.sections || []).map(section => {
      const items = state.items.filter(item => item.pageId === p.id && (!selected || item.entityId === selected) && item.sectionTitle === section.title);
      if (!items.length) return '';
      return '<section class="section"><div class="section-heading"><h3>' + esc(section.title) + '</h3>' + (section.note ? '<p>' + esc(section.note) + '</p>' : '') + '</div>' + items.map(row).join('') + (section.preview === 'hitbox' ? '<div id="hitbox-preview" class="hitbox-preview"></div>' : '') + '</section>';
    }).join('');
  }
  function renderMoves(p) {
    if (!entityId || !p.moves.some(m => m.id === entityId)) entityId = 'overview';
    let picker = '<div class="entity-picker"><div class="picker-group"><span class="group-label">全部招式</span><button data-entity="overview" class="' + (entityId === 'overview' ? 'active' : '') + '">总览</button></div>';
    [...new Set(p.moves.map(m => m.group))].forEach(group => { picker += '<div class="picker-group"><span class="group-label">' + esc(group) + '</span>' + p.moves.filter(m => m.group === group).map(m => '<button data-entity="' + esc(m.id) + '" class="' + (entityId === m.id ? 'active' : '') + '">' + esc(m.label) + '</button>').join('') + '</div>'; });
    picker += '</div>';
    return heading(p.title,p.hint) + picker + (entityId === 'overview' ? overview(p) : '<h3>' + esc(p.moves.find(m=>m.id===entityId).label) + '</h3><div id="move-summary" class="summary"></div>' + sections(p,entityId));
  }
  function overview(p) {
    const keys = ['damage','knockbackX','launchY'];
    return '<p class="muted small">点击一行打开这招的参数。高亮格子是改过的数值。</p><div class="table-wrap"><table><thead><tr>' + ['招式','伤害','击退','击飞','前摇','判定','接招前','收招','总帧数'].map(s=>'<th>'+s+'</th>').join('') + '</tr></thead><tbody>' + p.moves.map(meta => {
      const source = M.moveSource(state,values,meta.id), original = M.moveSource(state,{},meta.id), f=M.moveFrames(state,values,meta.id), df=M.moveFrames(state,{},meta.id);
      const cells = keys.map(k=>'<td class="'+(!equal(source[k],original[k])?'modified-cell':'')+'">'+esc(fmt(Math.round(source[k])))+'</td>').join('') + ['startup','active','recovery','tail','total'].map(k=>'<td class="'+(f[k]!==df[k]?'modified-cell':'')+'">'+esc(fmt(f[k]))+'</td>').join('');
      return '<tr data-entity="'+esc(meta.id)+'" tabindex="0" role="button" aria-label="调整'+esc(meta.label)+'"><td>'+esc(meta.label)+'</td>'+cells+'</tr>';
    }).join('') + '</tbody></table></div>';
  }
  function renderEnemies(p) {
    if (!p.kinds.some(k=>k.id===entityId)) entityId = p.kinds[0].id;
    const selected = p.kinds.find(k=>k.id===entityId);
    return heading(p.title,p.hint) + '<div class="entity-picker"><div class="picker-group">' + p.kinds.map(k=>'<button data-entity="'+esc(k.id)+'" class="'+(entityId===k.id?'active':'')+'">'+esc(k.label)+'</button>').join('') + '</div></div><h3>'+esc(selected.label)+'</h3><p class="muted entity-blurb">'+esc(selected.blurb)+'</p>'+sections(p,entityId);
  }
  function renderDynamic() {
    if (pageId !== 'moves' || entityId === 'overview' || query) return;
    const f = M.moveFrames(state,values,entityId), source=M.moveSource(state,values,entityId);
    if ($('#move-summary')) $('#move-summary').textContent = '伤害 '+fmt(source.damage)+' · 前摇 '+f.startup+' 帧 · 判定 '+f.active+' 帧 · 接招前 '+f.recovery+' 帧 · 收招 '+f.tail+' 帧 · 共 '+f.total+' 帧';
    const preview=$('#hitbox-preview'); if (!preview) return;
    const b=source.hitbox || {}, x=Number(b.x || 0),y=Number(b.y || 0),w=Math.max(0,Number(b.width || 0)),h=Math.max(0,Number(b.height || 0));
    const left=Math.min(-55,x-w/2-25),right=Math.max(70,x+w/2+25),top=Math.min(-195,y-h/2-25),bottom=Math.max(35,y+h/2+25);
    preview.innerHTML='<svg viewBox="'+[left,top,right-left,bottom-top].join(' ')+'" preserveAspectRatio="xMidYMid meet" role="img" aria-label="主角与攻击判定框等比示意"><line x1="'+left+'" y1="0" x2="'+right+'" y2="0" stroke="#4e5e6c" stroke-width="1" vector-effect="non-scaling-stroke"/><line x1="0" y1="'+top+'" x2="0" y2="'+bottom+'" stroke="#2d3b47" stroke-width="1" vector-effect="non-scaling-stroke"/><rect x="-32" y="-168" width="64" height="168" fill="#66717e" stroke="#bbc8d5" stroke-width="1" vector-effect="non-scaling-stroke"/><path d="M 10 -108 L 27 -98 L 10 -88" fill="none" stroke="#e6edf4" stroke-width="2" vector-effect="non-scaling-stroke"/><rect x="'+(x-w/2)+'" y="'+(y-h/2)+'" width="'+w+'" height="'+h+'" fill="#7598b544" stroke="#adc6dc" stroke-width="2" vector-effect="non-scaling-stroke"/><circle cx="0" cy="0" r="3" fill="#e4ebf1"/></svg><div class="preview-legend"><span><i class="swatch player"></i>主角 64 × 168，面朝右</span><span><i class="swatch box"></i>攻击判定框</span></div>';
  }
  function syncParameters() {
    document.querySelectorAll('[data-row]').forEach(el => {
      const item=state.items.find(i=>i.path===el.dataset.row), value=disp(item); el.classList.toggle('modified',itemChanged(item));
      el.querySelectorAll('input').forEach(input=>{ if(input.type==='checkbox'){input.checked=value; input.nextElementSibling.textContent=value?'开启':'关闭';}else if(document.activeElement!==input) input.value=value; });
      el.querySelector('.restore').hidden=!itemChanged(item);
      el.querySelector('.range-warning').textContent=typeof value==='number'&&(value<item.min||value>item.max)?'超出常用范围':'';
      el.querySelector('.default-line').textContent='默认 '+fmt(disp(item,{}))+(item.unit?' '+item.unit:'');
    });
  }
  function waveData(){return clone(values['encounters/waves'] || state.defaults['encounters/waves']);}
  function kindLabel(id){return page('enemies').kinds.find(k=>k.id===id)?.label || id;}
  function waveHealth(w){return [...(w.spawns||[]),...(w.reinforce||[])].reduce((sum,id)=>sum+Number(values['encounters/kinds/'+id+'/hp']??state.defaults['encounters/kinds/'+id+'/hp']??0),0);}
  function tags(w, seal, wi, field) {
    return '<div class="enemy-tags">'+(w[field]||[]).map((id,index)=>'<span class="enemy-tag">'+esc(kindLabel(id))+'<button data-wave-remove="'+[seal,wi,field,index].join(':')+'" aria-label="删除'+esc(kindLabel(id))+'">×</button></span>').join('')+'</div><select aria-label="添加'+(field==='spawns'?'敌人':'增援')+'" data-wave-add="'+[seal,wi,field].join(':')+'"><option value="">＋ 添加'+(field==='spawns'?'敌人':'增援')+'</option>'+page('enemies').kinds.map(k=>'<option value="'+esc(k.id)+'">'+esc(k.label)+'</option>').join('')+'</select>';
  }
  function renderWaves(p) {
    const data=waveData(),defaults=state.defaults['encounters/waves'];
    return heading(p.title,p.hint,'<button data-reset-waves class="subtle">恢复默认波次</button>')+'<div class="wave-columns">'+p.sealLabels.map((label,seal)=>'<section class="wave-column"><h3>'+esc(label)+'</h3>'+(data[seal]||[]).map((w,wi)=>'<article id="wave-'+seal+'-'+wi+'" class="wave-card '+(!equal(w,defaults[seal]?.[wi])?'modified':'')+'"><div class="wave-header"><input aria-label="波次名称" value="'+esc(w.label)+'" data-wave-field="'+[seal,wi,'label'].join(':')+'"><button data-wave-delete="'+seal+':'+wi+'" aria-label="删除这波">×</button></div><div class="wave-field"><label>敌人</label>'+tags(w,seal,wi,'spawns')+(!w.spawns?.length?'<p class="wave-warning">至少添加一名敌人才能应用</p>':'')+'</div><div class="wave-field"><label>增援</label>'+tags(w,seal,wi,'reinforce')+'</div><div class="wave-field"><label>剩几只时增援</label><input type="number" min="1" step="1" value="'+(w.reinforce_at??1)+'" data-wave-field="'+[seal,wi,'reinforce_at'].join(':')+'" '+(!w.reinforce?.length?'disabled':'')+'></div><div class="wave-field"><label>同时最多几只出刀</label><input type="number" min="1" step="1" value="'+(w.max_attackers??1)+'" data-wave-field="'+[seal,wi,'max_attackers'].join(':')+'"></div><div class="wave-hp">这波总血量 '+fmt(waveHealth(w))+'</div></article>').join('')+'<button class="add-wave" data-wave-new="'+seal+'">＋ 添加一波</button></section>').join('')+'</div>';
  }
  function changeWave(fn) { const data=waveData();fn(data);const next=clone(values);if(equal(data,state.defaults['encounters/waves']))delete next['encounters/waves'];else next['encounters/waves']=data;commit(next);renderContent(); }
  function renderPresets(){return heading('方案','把一套调整保存下来，随时切换。')+'<section class="presets-save"><h3>保存当前改动</h3><p>包含已应用和还没应用的全部自定义数值。</p><form id="save-preset" class="save-form"><input id="preset-name" placeholder="方案名字" maxlength="80" aria-label="方案名字" required><button class="primary" type="submit">保存为方案</button></form></section><div>'+state.presets.map(entry=>{const name=typeof entry==='string'?entry:entry.name;return '<div class="preset-row"><span class="preset-name">'+esc(name)+'</span><button data-preset-load="'+esc(name)+'">读取</button><button data-preset-delete="'+esc(name)+'" class="'+(deleteConfirm===name?'danger':'subtle')+'">'+(deleteConfirm===name?'确认删除':'删除')+'</button>'+(deleteConfirm===name?'<button data-cancel-delete class="subtle">取消</button>':'')+'</div>';}).join('')+'</div>'+(!state.presets.length?'<p class="empty">还没有保存的方案。</p>':'')+'<p class="draft-note">读取方案会替换当前草稿；应用后才会写入游戏数值。</p>';}
  function searchResults(){const q=query.toLowerCase();const results=[];state.items.forEach(item=>{const e=entity(item),p=page(item.pageId);if([item.label,item.help,item.sectionTitle,p.title,p.hint,e?.label,e?.blurb,e?.group].join(' ').toLowerCase().includes(q))results.push({item,location:p.title+(e?' · '+e.label:'')+' · '+item.label,label:item.label,help:item.help});});if(['波次','敌人','增援','封印',...page('waves').sealLabels].some(s=>s.includes(query)))results.push({page:'waves',location:'波次',label:'波次安排',help:'调整敌人、增援与同时出刀数量。'});return heading('搜索结果','“'+query+'” · '+results.length+' 项')+'<div class="search-results">'+results.map(r=>'<button class="search-result" '+(r.item?'data-jump="'+esc(r.item.path)+'"':'data-page="'+r.page+'"')+'><div class="result-location">'+esc(r.location)+'</div><strong>'+esc(r.label)+'</strong><p>'+esc(r.help)+'</p></button>').join('')+(!results.length?'<p class="empty">没有找到对应参数，试试更短的词。</p>':'')+'</div>';}
  function renderContent(){$('#content').classList.toggle('scene-page',!query&&page()?.template==='scene');if(query){$('#content').innerHTML=searchResults();return;}const p=page();if(p?.template==='scene'){$('#content').innerHTML='<div id="scene-root"></div>';window.SceneEditor.mount($('#scene-root'),p);return;}$('#content').innerHTML=pageId==='presets'?renderPresets():p.template==='moves'?renderMoves(p):p.template==='enemies'?renderEnemies(p):p.template==='waves'?renderWaves(p):heading(p.title,p.hint)+sections(p);renderDynamic();}
  function render(){renderNavigation();renderContent();renderSide();updateTop();}
  function navigate(id,selected){pageId=id;entityId=selected||null;query='';$('#search').value='';deleteConfirm=null;render();window.scrollTo({top:0,behavior:'smooth'});}
  function jump(path){const item=state.items.find(i=>i.path===path);if(!item)return;if(page(item.pageId)?.template==='scene')window.SceneEditor.reveal();navigate(item.pageId,item.entityId);requestAnimationFrame(()=>{const el=document.getElementById(rowId(path));if(el){el.scrollIntoView({behavior:'smooth',block:'center'});el.classList.add('flash');setTimeout(()=>el.classList.remove('flash'),2200);}});}
  async function apply(scene){if(busy)return;const focused=document.activeElement;if(focused?.matches('input[type=number]')&&(focused.value.trim()===''||!Number.isFinite(Number(focused.value))||(focused.dataset.waveField&&(!Number.isInteger(Number(focused.value))||Number(focused.value)<1)))){notify('请输入有效的数字后再应用。',true);return;}finishGesture();busy=true;updateTop();try{await window.SceneEditor.prepareApply();const submittedValues=clone(values);const result=await api('/api/apply','POST',{values:submittedValues,baseRevision});baseRevision=result.revision;state.revision=result.revision;applied=clone(submittedValues);state.values=clone(submittedValues);saveDraft();$('#conflict').hidden=true;if(scene){state.game=await api('/api/game/launch','POST',{scene});if(state.game.game)state.game=state.game.game;notify('已应用，'+(scene==='rain'?'雨街':'训练场')+'已启动。');}else notify('改动已应用。');}catch(error){if(error.status===409){$('#conflict').hidden=false;saveDraft();}else notify(error.message,true);}finally{busy=false;renderSide();updateTop();}}
  function rebaseDraft(draft,previous,next){const merged=clone(next);for(const key of new Set([...Object.keys(previous),...Object.keys(draft)])){if(equal(previous[key],draft[key]))continue;if(Object.hasOwn(draft,key))merged[key]=clone(draft[key]);else delete merged[key];}return merged;}
  async function reload(){try{const fresh=await api('/api/state');const previous=clone(applied);values=rebaseDraft(values,previous,fresh.values);history=history.map(draft=>rebaseDraft(draft,previous,fresh.values));future=future.map(draft=>rebaseDraft(draft,previous,fresh.values));gesture=null;state=fresh;applied=clone(state.values);baseRevision=state.revision;saveDraft();$('#conflict').hidden=true;render();notify('已重新读取文件，你还没应用的改动仍保留在草稿里。');}catch(error){notify(error.message,true);}}
  document.addEventListener('click',async event=>{
    const button=event.target.closest('button,[data-entity]');if(!button||!state)return;
    try{
      if(button.id==='pending-count'||button.id==='close-changes'){const open=$('#changes-panel').classList.toggle('open');$('#pending-count').setAttribute('aria-expanded',open);return;}
      if(button.dataset.sceneReset){const next=clone(values);button.dataset.sceneReset.split('|').forEach(k=>delete next[k]);commit(next);render();return;}
      if(button.dataset.page){navigate(button.dataset.page);return;}
      if(button.dataset.entity){entityId=button.dataset.entity;renderContent();return;}
      if(button.dataset.jump){jump(button.dataset.jump);return;}
      if(button.dataset.reset){restore(state.items.find(i=>i.path===button.dataset.reset));return;}
      if(button.hasAttribute('data-reset-waves')){const next=clone(values);delete next['encounters/waves'];commit(next);render();return;}
      if(button.hasAttribute('data-reset-all')){allConfirm=true;renderSide();return;}
      if(button.hasAttribute('data-cancel-reset')){allConfirm=false;renderSide();return;}
      if(button.hasAttribute('data-confirm-reset')){commit({});render();return;}
      if(button.dataset.waveRemove){const [s,w,field,index]=button.dataset.waveRemove.split(':');changeWave(d=>{d[s][w][field].splice(Number(index),1);if(field==='reinforce'&&!d[s][w][field].length){delete d[s][w].reinforce;delete d[s][w].reinforce_at;}});return;}
      if(button.dataset.waveDelete){const [s,w]=button.dataset.waveDelete.split(':');changeWave(d=>d[s].splice(Number(w),1));return;}
      if(button.dataset.waveNew!==undefined){const s=Number(button.dataset.waveNew);changeWave(d=>{while(d.length<=s)d.push([]);d[s].push({label:'新的一波',spawns:['grunt'],max_attackers:2});});return;}
      if(button.dataset.presetLoad){const result=await api('/api/presets?name='+encodeURIComponent(button.dataset.presetLoad));commit(result.values);render();notify('方案已读入草稿，点击应用后生效。');return;}
      if(button.dataset.presetDelete){const name=button.dataset.presetDelete;if(deleteConfirm!==name){deleteConfirm=name;renderContent();return;}const result=await api('/api/presets','DELETE',{name});state.presets=result.presets;deleteConfirm=null;renderContent();notify('方案已删除。');return;}
      if(button.hasAttribute('data-cancel-delete')){deleteConfirm=null;renderContent();return;}
      if(button.id==='apply-rain')await apply('rain');
      if(button.id==='apply-training')await apply('training');
      if(button.id==='apply-only')await apply();
      if(button.id==='undo')undo();
      if(button.id==='redo')redo();
      if(button.id==='reload-state')await reload();
      if(button.id==='stop-game'){state.game=await api('/api/game/stop','POST',{});if(state.game.game)state.game=state.game.game;updateTop();notify('游戏已停止。');}
    }catch(error){notify(error.message,true);}
  });
  document.addEventListener('submit',async event=>{if(event.target.id!=='save-preset')return;event.preventDefault();try{const name=$('#preset-name').value.trim();if(!name){notify('请填写方案名字。',true);return;}const result=await api('/api/presets','POST',{name,values});state.presets=result.presets;renderContent();notify('方案已保存。');}catch(error){notify(error.message,true);}});
  const hintFor=el=>{const row=el.closest?.('[data-row]');if(!row)return;const item=state.items.find(i=>i.path===row.dataset.row);if(item)$('#hint').textContent=item.label+'：'+(item.help||'')+'  默认 '+fmt(disp(item,{}))+(item.unit?' '+item.unit:'');};
  document.addEventListener('mouseover',event=>{if(state)hintFor(event.target);});
  document.addEventListener('focusin',event=>{if(state)hintFor(event.target);});
  document.addEventListener('pointerdown',event=>{if(event.target.matches('input[type=range][data-item]'))gesture=clone(values);});
  document.addEventListener('input',event=>{const input=event.target;if(input.id==='search'){query=input.value.trim();renderNavigation();renderContent();return;}if(input.dataset.waveField){if(input.type==='number'&&(!input.value.trim()||!Number.isInteger(Number(input.value))||Number(input.value)<1))return;if(!gesture)gesture=clone(values);const [s,w,key]=input.dataset.waveField.split(':');const data=waveData();data[s][w][key]=input.type==='number'?Number(input.value):input.value;const next=clone(values);if(equal(data,state.defaults['encounters/waves']))delete next['encounters/waves'];else next['encounters/waves']=data;commit(next,false);return;}if(input.matches('input[data-item]')&&input.type!=='checkbox'){if(input.value.trim()===''||!Number.isFinite(Number(input.value)))return;const item=state.items.find(i=>i.path===input.dataset.item);if(!gesture)gesture=clone(values);edit(item,Number(input.value),false);}});
  document.addEventListener('change',event=>{
    const input=event.target;
    if(input.dataset.item){const item=state.items.find(i=>i.path===input.dataset.item);if(input.type==='checkbox')edit(item,input.checked);else{if(input.value.trim()===''||!Number.isFinite(Number(input.value))){notify('请输入有效的数字。',true);input.value=disp(item);}else if(!equal(Number(input.value),disp(item)))edit(item,Number(input.value),!gesture);finishGesture();updateTop();}return;}
    if(input.dataset.waveField){finishGesture();const [s,w,key]=input.dataset.waveField.split(':');if(input.type==='number'&&(!Number.isInteger(Number(input.value))||Number(input.value)<1)){notify('这里需要填写正整数。',true);renderContent();return;}changeWave(d=>d[s][w][key]=input.type==='number'?Number(input.value):input.value);return;}
    if(input.dataset.waveAdd&&input.value){const [s,w,field]=input.dataset.waveAdd.split(':');changeWave(d=>{(d[s][w][field]??=[]).push(input.value);if(field==='reinforce')d[s][w].reinforce_at??=1;});}
  });
  document.addEventListener('keydown',event=>{
    if(!state)return;
    if((event.ctrlKey||event.metaKey)&&event.key.toLowerCase()==='s'){event.preventDefault();apply();}
    if((event.ctrlKey||event.metaKey)&&event.key.toLowerCase()==='z'){event.preventDefault();event.shiftKey?redo():undo();}
    if((event.ctrlKey||event.metaKey)&&event.key.toLowerCase()==='y'){event.preventDefault();redo();}
    if((event.ctrlKey||event.metaKey)&&event.key.toLowerCase()==='k'){event.preventDefault();$('#search').focus();}
    if((event.key==='Enter'||event.key===' ')&&event.target.matches('tr[data-entity]')){event.preventDefault();entityId=event.target.dataset.entity;renderContent();}
  });
  window.addEventListener('beforeunload',()=>{if(state)saveDraft();});
  window.SceneEditor.init({get state(){return state;},get values(){return values;},commit:(next,remember=true)=>commit(next,remember),notify,api,sectionsHtml:p=>sections(p)});
  // 页面策略禁止 style 属性，默认值刻度的位置用脚本设。
  new MutationObserver(()=>{for(const r of document.querySelectorAll('input[type=range][data-def]')){r.style.setProperty('--def',r.dataset.def);r.removeAttribute('data-def');}}).observe($('#content'),{childList:true,subtree:true});
  async function init(){try{state=await api('/api/state');values=clone(state.values);applied=clone(state.values);baseRevision=state.revision;draftKey='nightcrow-modifier-v1:'+state.projectRoot;try{const saved=JSON.parse(localStorage.getItem(draftKey)||'null');if(saved&&saved.values&&typeof saved.values==='object'&&!Array.isArray(saved.values)){values=saved.values;if(saved.applied&&typeof saved.applied==='object'&&!Array.isArray(saved.applied))applied=saved.applied;baseRevision=saved.baseRevision||state.revision;notify('已恢复上次还没应用的草稿。');if(baseRevision!==state.revision)$('#conflict').hidden=false;}}catch{notify('上次草稿无法读取，本次已载入文件中的数值。',true);}render();setInterval(async()=>{if(busy)return;try{const fresh=await api('/api/state');state.game=fresh.game;updateTop();}catch{/* 断线后的下一次轮询会继续连接。 */}},5000);}catch(error){$('#content').innerHTML='<h2>暂时无法读取修改器</h2><p class="muted connection-error">'+esc(error.message)+'。请重新打开修改器。</p>';notify(error.message,true);}}
  init();
})();
