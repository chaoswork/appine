// Selection Assistant v0.8
let api = null, curText = '', curRect = null, abortCtrl = null, clickHandler = null, hideTimer = null;

// 可配置项
let cfg = { url: 'https://api.openai.com/v1', key: '', models: ['gpt-3.5-turbo', 'gpt-4o', 'deepseek-reasoner'], trans: 'gpt-3.5-turbo', trans_system_prompt: 'Translate to Chinese. Only output translation.', enableTrans: true, enableCapture: true, captureKey: 'c', enableSearch: true, searchUrl: 'https://www.google.com/search?q=' };


let sessions = [], activePop = null, activeSide = null;

const iCopy = `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="13" height="13" rx="2" ry="2"></rect><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"></path></svg>`;
const iEdit = `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"></path><path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"></path></svg>`;
const iRetry = `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 2v6h-6M3 12a9 9 0 1 0 2.6-6.4L2 8"/></svg>`;
const iMore = `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="1"/><circle cx="12" cy="5" r="1"/><circle cx="12" cy="19" r="1"/></svg>`;

const loadData = async () => {
  try {
    let d = null;
    if (api.getStorage) d = await api.getStorage(['ap_cfg', 'ap_sess']);

    if (d && (d.ap_cfg || d.ap_sess)) {
      if (d.ap_cfg) Object.assign(cfg, JSON.parse(d.ap_cfg));
      if (d.ap_sess) sessions = JSON.parse(d.ap_sess);
    } else if (window.__APPINE_STORAGE__) {
      if (window.__APPINE_STORAGE__.ap_cfg) Object.assign(cfg, JSON.parse(window.__APPINE_STORAGE__.ap_cfg));
      if (window.__APPINE_STORAGE__.ap_sess) sessions = JSON.parse(window.__APPINE_STORAGE__.ap_sess);
    } else {
      Object.assign(cfg, JSON.parse(localStorage.getItem('ap_cfg')||'{}'));
      sessions = JSON.parse(localStorage.getItem('ap_sess')||'[]');
    }
  } catch(e){
    console.error('[Appine-Debug] ❌ loadData 报错:', e);
  }
};

const saveData = () => {
  const c = JSON.stringify(cfg), s = JSON.stringify(sessions.slice(0,20));
  try {
    if (api.setStorage) {
      api.setStorage({ ap_cfg: c, ap_sess: s });
    }
    if (window.webkit?.messageHandlers?.appineSaveData) {
      window.webkit.messageHandlers.appineSaveData.postMessage({ ap_cfg: c, ap_sess: s });
      window.__APPINE_STORAGE__ = { ap_cfg: c, ap_sess: s };
    }
    localStorage.setItem('ap_cfg', c); localStorage.setItem('ap_sess', s);
  } catch(e){}
};

const renderMD = t => (t||'').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/```(\w*)\n([\s\S]*?)```/g, (m,l,c)=>`<pre class="ap-md-pre"><code>${c}</code></pre>`).replace(/`([^`\n]+)`/g, '<code class="ap-md-code">$1</code>').replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');

function initUI() {
  if (document.getElementById('ap-style')) return;
  // 给所有根节点加上 pointer-events: auto !important; 抵抗宿主网页的禁用
  document.head.insertAdjacentHTML('beforeend', `<style id="ap-style">
    .ap-card { position:absolute; z-index:2147483647; background:#fff; border:1px solid #e0e0e0; border-radius:12px; box-shadow:0 8px 24px rgba(0,0,0,.12); font-family:sans-serif; display:none; flex-direction:column; pointer-events:auto !important; }
    .ap-btn { border:none; background:transparent; padding:8px 12px; cursor:pointer; font-size:14px; border-radius:4px; color:#333; } .ap-btn:hover { background:#f0f0f0; }
    .ap-header { display:flex; justify-content:space-between; align-items:center; padding:12px 16px; font-weight:500; border-bottom:1px solid #eee; }
    .ap-msgs { flex:1; padding:16px; overflow-y:auto; display:flex; flex-direction:column; gap:24px; min-height:300px; max-height:500px; }
    .ap-input-wrap { padding:0 16px 16px; }
    .ap-input-box { border:1px solid #dadce0; background:transparent; border-radius:24px; padding:12px 16px; display:flex; flex-direction:column; gap:8px; transition:border 0.2s; }
    .ap-input-box:focus-within { border-color:#1a73e8; }
    .ap-textarea { width:100%; border:none; outline:none; resize:none; background:transparent; font-family:inherit; font-size:15px; line-height:1.5; min-height:24px; max-height:120px; }
    .ap-toolbar { display:flex; justify-content:space-between; align-items:center; color:#5f6368; font-size:14px; }
    .ap-icon { cursor:pointer; padding:4px 8px; border-radius:16px; display:flex; align-items:center; gap:4px; } .ap-icon:hover { background:rgba(0,0,0,.05); color:#202124; }
    .ap-user-row { display:flex; justify-content:flex-end; gap:8px; } .ap-user-row:hover .ap-user-acts { opacity:1; }
    .ap-user-acts { display:flex; opacity:0; transition:opacity .2s; margin-top:8px; }
    .ap-user-bubble { background:#f0f4f9; padding:12px 16px; border-radius:18px; font-size:15px; max-width:80%; white-space:pre-wrap; word-wrap:break-word; }
    .ap-ai-row { display:flex; gap:12px; } .ap-ai-content { flex:1; min-width:0; }
    .ap-ai-text { font-size:15px; line-height:1.6; word-wrap:break-word; white-space:pre-wrap; }
    .ap-ai-acts { display:flex; gap:8px; margin-top:8px; position:relative; color:#5f6368; }
    .ap-think-det { margin-bottom:12px; } .ap-think-sum { cursor:pointer; color:#5f6368; font-size:13px; }
    .ap-think-content { padding:10px; border-left:2px solid #e8eaed; color:#5f6368; font-size:14px; margin-top:8px; white-space:pre-wrap; background:#fcfcfc; }
    .ap-md-pre { background:#f8f9fa; border:1px solid #e8eaed; padding:12px; border-radius:8px; overflow-x:auto; font-family:monospace; font-size:13px; }
    .ap-md-code { background:#f1f3f4; padding:2px 6px; border-radius:4px; color:#d93025; font-family:monospace; }
    .ap-float { position:fixed; right:-20px; bottom:50px; width:44px; height:44px; background:#fff; border:1px solid #ddd; border-radius:50%; display:flex; align-items:center; justify-content:center; cursor:pointer; z-index:2147483646; transition:right .3s; font-size:20px; box-shadow:-2px 2px 8px rgba(0,0,0,.1); pointer-events:auto !important; } .ap-float:hover { right:20px; }
    .ap-side { position:fixed; right:20px; bottom:105px; width:700px; height:600px; max-width:calc(100vw - 40px); max-height:calc(100vh - 120px); background:#fff; border:1px solid #ddd; border-radius:16px; box-shadow:0 12px 32px rgba(0,0,0,.15); z-index:2147483647; display:none; overflow:hidden; pointer-events:auto !important; }
    .ap-menu { display:none; position:absolute; top:100%; left:60px; background:#fff; border:1px solid #dadce0; border-radius:8px; padding:8px; z-index:10; width:100px; box-shadow:0 4px 12px rgba(0,0,0,.1); flex-direction:column; gap:4px; }
    .ap-menu-item { padding:6px; cursor:pointer; border-radius:4px; font-size:13px; } .ap-menu-item:hover { background:#f0f4f9; }
  </style>`);

  const inputHtml = (id, mid) => `<div class="ap-input-wrap"><div class="ap-input-box"><textarea class="ap-textarea" id="${id}" placeholder="输入指令... (Enter 发送)"></textarea><div class="ap-toolbar"><div style="display:flex;gap:12px"><div class="ap-icon">＋</div><div class="ap-icon">⚯ 工具 <span style="width:6px;height:6px;background:#1a73e8;border-radius:50%"></span></div></div><select id="${mid}" style="border:none;outline:none;background:transparent;color:#5f6368;cursor:pointer"></select></div></div></div>`;

  const inpStyle = "width:100%;padding:8px;box-sizing:border-box;border:1px solid #dadce0;border-radius:4px;font-size:14px;color:#333;outline:none;";
  const inpWrap = (lbl, id, placeholder, type="text") => `<div style="margin-bottom:12px"><div style="font-size:12px;color:#5f6368;margin-bottom:4px">${lbl}</div><input id="${id}" type="${type}" placeholder="${placeholder}" style="${inpStyle}"></div>`;
  const secTitle = (t) => `<div style="font-size:14px;font-weight:bold;color:#1a73e8;margin:16px 0 8px;border-bottom:1px solid #eee;padding-bottom:4px">${t}</div>`;

  // 设置面板也加上 pointer-events:auto !important;
  document.body.insertAdjacentHTML('beforeend', `
    <div id="ap-act" class="ap-card" style="padding:6px;flex-direction:row;gap:4px"></div>
    <div id="ap-trans" class="ap-card" style="width:380px"><div class="ap-header"><span>🌐 翻译</span><span style="cursor:pointer" data-act="hide">✕</span></div><div class="ap-msgs" style="min-height:100px;max-height:300px"><div class="ap-ai-row"><div style="font-size:20px">✨</div><div class="ap-ai-content"><div id="ap-trans-res" class="ap-ai-text"></div><div class="ap-ai-acts"><div class="ap-icon" data-act="copyTrans">${iCopy}</div></div></div></div></div></div>
    <div id="ap-pop" class="ap-card" style="width:420px"><div class="ap-header"><span>✨ 问问 AI</span><span style="cursor:pointer" data-act="hide">✕</span></div><div id="ap-pop-msg" class="ap-msgs"></div>${inputHtml('ap-pop-in', 'ap-pop-mod')}</div>
    <div id="ap-float" class="ap-float" data-act="toggleSide">✨</div>
    <div id="ap-side" class="ap-side"><div style="display:flex;height:100%"><div style="width:220px;background:#f8f9fa;border-right:1px solid #e8eaed;display:flex;flex-direction:column"><div class="ap-header"><span>会话记录</span><span style="cursor:pointer" data-act="set">⚙️</span></div><div id="ap-side-list" style="flex:1;overflow-y:auto"></div></div><div style="flex:1;display:flex;flex-direction:column"><div class="ap-header"><span id="ap-side-title">选择会话</span><span style="cursor:pointer" data-act="hide">✕</span></div><div id="ap-side-msg" class="ap-msgs"></div>${inputHtml('ap-side-in', 'ap-side-mod')}</div></div></div>
    <div id="ap-set" style="position:fixed;inset:0;background:rgba(0,0,0,.5);z-index:2147483648;display:none;align-items:center;justify-content:center;pointer-events:auto !important;"><div style="background:#fff;width:400px;max-height:85vh;overflow-y:auto;padding:24px;border-radius:12px;box-shadow:0 12px 32px rgba(0,0,0,.2)"><h3 style="margin-top:0;color:#333">Settings</h3>
      ${secTitle('API & Chat')}
      ${inpWrap('Base URL', 'cfg-url', 'https://api.openai.com/v1')}
      ${inpWrap('API Key', 'cfg-key', 'sk-...', 'password')}
      ${inpWrap('Chat Models (comma separated)', 'cfg-mods', 'gpt-3.5-turbo, gpt-4o')}

      ${secTitle('Translation')}
      <label style="display:flex;align-items:center;font-size:13px;color:#333;margin-bottom:8px;cursor:pointer"><input type="checkbox" id="cfg-en-trans" style="margin-right:8px"> Enable Translation</label>
      ${inpWrap('Translation Model', 'cfg-trans', 'gpt-3.5-turbo')}
      ${inpWrap('System Prompt', 'cfg-trans-prompt', 'Translate to 中文. Only output translation.')}

      ${secTitle('Org Capture')}
      <label style="display:flex;align-items:center;font-size:13px;color:#333;margin-bottom:8px;cursor:pointer"><input type="checkbox" id="cfg-en-cap" style="margin-right:8px"> Enable Capture</label>
      ${inpWrap('Capture Template Key', 'cfg-cap-key', 'c')}

      ${secTitle('Web Search')}
      <label style="display:flex;align-items:center;font-size:13px;color:#333;margin-bottom:8px;cursor:pointer"><input type="checkbox" id="cfg-en-search" style="margin-right:8px"> Enable Search</label>
      ${inpWrap('Search URL Template', 'cfg-search-url', 'https://www.google.com/search?q=')}

      <div style="text-align:right;margin-top:16px"><button class="ap-btn" data-act="cancelSet" style="border:1px solid #dadce0;margin-right:8px">Cancel</button><button class="ap-btn" style="background:#1a73e8;color:#fff;border:none" data-act="saveSet">Save</button></div>
    </div></div>
  `);
}

const renderActBtns = () => {
  const c = document.getElementById('ap-act'); if(!c) return;
  let html = '';
  if(cfg.enableTrans) html += `<button class="ap-btn" data-act="trans">🌐 Translate</button>`;
  html += `<button class="ap-btn" data-act="ask">✨ Ask AI</button>`;
  if(cfg.enableCapture) html += `<button class="ap-btn" data-act="capture">📝 Capture</button>`;
  if(cfg.enableSearch) html += `<button class="ap-btn" data-act="search">🔍 Search</button>`;
  c.innerHTML = html;
};

const posCard = (id) => {
  const c = document.getElementById(id); c.style.display = 'flex';

  if (id === 'ap-act') {
    c.style.flexDirection = 'row'; // 默认横排

    const active = document.activeElement;
    const isInput = active && (active.tagName === 'INPUT' || active.tagName === 'TEXTAREA' || active.isContentEditable);

    let l, t;
    if (isInput) {
      const rect = active.isContentEditable ? curRect : active.getBoundingClientRect();
      l = Math.max(0, window.scrollX + rect.left); // 左侧与输入框对齐

      // 防止右侧超出屏幕
      if (l + c.offsetWidth > window.scrollX + window.innerWidth) {
        l = Math.max(0, window.scrollX + window.innerWidth - c.offsetWidth - 10);
      }

      const spaceNeeded = c.offsetHeight + 10;
      if (rect.top < spaceNeeded) {
        // 上方空间不够，在 body 顶部插入空白区域把页面往下挤
        let spacer = document.getElementById('ap-top-spacer');
        if (!spacer) {
          document.body.insertAdjacentHTML('afterbegin', '<div id="ap-top-spacer" style="height:0; transition:height 0.2s; width:100%; pointer-events:none; background:transparent;"></div>');
          spacer = document.getElementById('ap-top-spacer');
        }
        const pushDown = spaceNeeded - rect.top + 5; // 计算需要往下挤多少像素
        spacer.style.height = pushDown + 'px';

        t = window.scrollY + 5; // 弹窗固定在页面最上方
      } else {
        // 空间足够，直接在输入框正上方显示
        t = window.scrollY + rect.top - spaceNeeded;
      }
    } else {
      // 按 rect 选择  
      // l = Math.max(0, window.scrollX + curRect.left);
      // t = window.scrollY + curRect.bottom + 10;
      // if (l + c.offsetWidth > window.scrollX + window.innerWidth) l = Math.max(0, window.scrollX + window.innerWidth - c.offsetWidth - 20);
      // if (t + c.offsetHeight > window.scrollY + window.innerHeight) t = Math.max(0, window.scrollY + curRect.top - c.offsetHeight - 10);
      // 非输入框场景：优先在离鼠标近的地方弹出（鼠标右下方）
      l = mouseX - 100; 
      t = mouseY + 15; 
      // 边界检查：如果右侧超出屏幕，放到鼠标左侧
      if (l + c.offsetWidth > window.scrollX + window.innerWidth) {
        l = mouseX - c.offsetWidth - 15;
        if (l < window.scrollX) l = window.scrollX + 10; // 保底防止左侧出界
      }

      // 边界检查：如果下方超出屏幕，放到鼠标上方
      if (t + c.offsetHeight > window.scrollY + window.innerHeight) {
        t = mouseY - c.offsetHeight - 15;
        if (t < window.scrollY) t = window.scrollY + 10; // 保底防止上方出界
      }
    }
    c.style.left = l + 'px'; c.style.top = t + 'px';
  } else {
    // 其他面板的定位逻辑保持不变
    let l = Math.max(0, window.scrollX + curRect.left), t = window.scrollY + curRect.bottom + 10;
    if (l + c.offsetWidth > window.scrollX + window.innerWidth) l = Math.max(0, window.scrollX + window.innerWidth - c.offsetWidth - 20);
    if (t + c.offsetHeight > window.scrollY + window.innerHeight) t = Math.max(0, window.scrollY + curRect.top - c.offsetHeight - 10);
    c.style.left = l + 'px'; c.style.top = t + 'px';
  }
};

const apHide = () => {
  ['ap-act','ap-trans','ap-pop','ap-side'].forEach(id => document.getElementById(id).style.display='none');
  if(abortCtrl) abortCtrl.abort();
  // 移除顶部空白区域
  const spacer = document.getElementById('ap-top-spacer');
  if (spacer) spacer.style.height = '0px';
};

const apToggleSide = () => { const s = document.getElementById('ap-side'); if(s.style.display==='flex') apHide(); else { renderList(); s.style.display='flex'; } };

const apSet = () => {
  document.getElementById('cfg-url').value=cfg.url;
  document.getElementById('cfg-key').value=cfg.key;
  document.getElementById('cfg-mods').value=cfg.models.join(',');
  document.getElementById('cfg-trans').value=cfg.trans;
  document.getElementById('cfg-trans-prompt').value=cfg.trans_system_prompt;
  document.getElementById('cfg-en-trans').checked=cfg.enableTrans;
  document.getElementById('cfg-en-cap').checked=cfg.enableCapture;
  document.getElementById('cfg-cap-key').value=cfg.captureKey;
  document.getElementById('cfg-en-search').checked=cfg.enableSearch;
  document.getElementById('cfg-search-url').value=cfg.searchUrl;
  document.getElementById('ap-set').style.display='flex';
};

const apSaveSet = () => {
  cfg.url=document.getElementById('cfg-url').value;
  cfg.key=document.getElementById('cfg-key').value;
  cfg.models=document.getElementById('cfg-mods').value.split(',').map(s=>s.trim());
  cfg.trans=document.getElementById('cfg-trans').value.trim();
  cfg.trans_system_prompt=document.getElementById('cfg-trans-prompt').value.trim();
  cfg.enableTrans=document.getElementById('cfg-en-trans').checked;
  cfg.enableCapture=document.getElementById('cfg-en-cap').checked;
  cfg.captureKey=document.getElementById('cfg-cap-key').value.trim() || 'c';
  cfg.enableSearch=document.getElementById('cfg-en-search').checked;
  cfg.searchUrl=document.getElementById('cfg-search-url').value.trim() || 'https://www.google.com/search?q=';
  saveData(); updMods(); renderActBtns(); document.getElementById('ap-set').style.display='none';
};

const updMods = () => ['ap-pop-mod','ap-side-mod'].forEach(id => { const el = document.getElementById(id); if(el) el.innerHTML = cfg.models.map(m=>`<option value="${m}">${m}</option>`).join(''); });

const getMsgHtml = (m, sid, idx, cid) => m.role === 'user' ?
  `<div class="ap-user-row"><div class="ap-user-acts"><div class="ap-icon" data-act="copy">${iCopy}</div><div class="ap-icon" data-act="edit" data-sid="${sid}" data-idx="${idx}" data-cid="${cid}">${iEdit}</div></div><div class="ap-user-bubble">${m.content}</div></div>` :
  `<div class="ap-ai-row"><div style="font-size:20px">✨</div><div class="ap-ai-content">${m.reasoning_content?`<details class="ap-think-det"><summary class="ap-think-sum">显示思路 ⌄</summary><div class="ap-think-content">${m.reasoning_content}</div></details>`:''}<div class="ap-ai-text">${renderMD(m.content)}</div><div class="ap-ai-acts"><div class="ap-icon" data-act="copy">${iCopy}</div><div class="ap-icon" data-act="retry" data-sid="${sid}" data-idx="${idx}" data-cid="${cid}">${iRetry}</div><div class="ap-icon" data-act="more">${iMore}</div><div class="ap-menu"><div class="ap-menu-item" data-act="tool" data-val="Tool 1">🔧 Tool 1</div><div class="ap-menu-item" data-act="tool" data-val="Tool 2">⚙️ Tool 2</div></div></div></div></div>`;

const renderMsgs = (cid, s) => { const c = document.getElementById(cid); c.innerHTML = (s.context ? `<div style="background:#f8f9fa;padding:10px;border-radius:8px;font-size:13px;color:#5f6368;margin-bottom:-10px">📌 引用：${s.context}</div>` : '') + s.messages.map((m,i) => getMsgHtml(m,s.id,i,cid)).join(''); c.scrollTop = c.scrollHeight; };
const renderList = () => { document.getElementById('ap-side-list').innerHTML = [...sessions].sort((a,b)=>b.updatedAt-a.updatedAt).map(s=>`<div style="padding:12px 16px;cursor:pointer;border-bottom:1px solid #f1f3f4;${s.id===activeSide?'background:#e8f0fe;color:#1a73e8;font-weight:500':''}" data-act="selSess" data-sid="${s.id}" data-val="${s.title}">${s.title}</div>`).join(''); };

const apEdit = (sid, idx, cid) => { const s = sessions.find(x=>x.id===sid); const t = s.messages[idx].content; s.messages=s.messages.slice(0,idx); saveData(); renderMsgs(cid,s); const inp = document.getElementById(cid==='ap-pop-msg'?'ap-pop-in':'ap-side-in'); inp.value=t; inp.focus(); };
const apRetry = (sid, idx, cid) => { const s = sessions.find(x=>x.id===sid); const t = s.messages[idx-1].content; s.messages=s.messages.slice(0,idx-1); saveData(); renderMsgs(cid,s); const inp = document.getElementById(cid==='ap-pop-msg'?'ap-pop-in':'ap-side-in'); inp.value=t; handleSend(sid, cid, inp.id, cid==='ap-pop-msg'?'ap-pop-mod':'ap-side-mod'); };

async function fetchAI(msgs, mod, onChunk, onDone, onErr) {
  if (!cfg.key) return onErr("未配置 API Key！");
  if (abortCtrl) abortCtrl.abort(); abortCtrl = new AbortController();
  try {
    const res = await fetch(`${cfg.url.replace(/\/+$/,'')}/chat/completions`, { method:'POST', headers:{'Content-Type':'application/json', 'Authorization':`Bearer ${cfg.key}`}, body:JSON.stringify({model:mod, messages:msgs, stream:true}), signal:abortCtrl.signal });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const reader = res.body.getReader(), dec = new TextDecoder("utf-8");
    while (true) {
      const { value, done } = await reader.read(); if (done) break;
      dec.decode(value, {stream:true}).split('\n').forEach(l => { if(l.startsWith('data: ') && l!=='data: [DONE]') try{ onChunk(JSON.parse(l.substring(6)).choices[0].delta); }catch(e){} });
    } onDone();
  } catch(e) { if(e.name !== 'AbortError') onErr(e.message); }
}

async function handleSend(sid, cid, inId, modId) {
  const inp = document.getElementById(inId), txt = inp.value.trim(), s = sessions.find(x=>x.id===sid), c = document.getElementById(cid); if(!txt||!s) return;
  inp.value=''; inp.disabled=true; s.messages.push({role:'user', content:txt}); s.updatedAt=Date.now(); saveData(); renderMsgs(cid, s); if(cid==='ap-side-msg') renderList();

  c.insertAdjacentHTML('beforeend', `<div class="ap-ai-row ap-stream"><div style="font-size:20px">✨</div><div class="ap-ai-content"><details class="ap-think-det" style="display:none" open><summary class="ap-think-sum">思考中...</summary><div class="ap-think-content"></div></details><div class="ap-ai-text">...</div></div></div>`); c.scrollTop = c.scrollHeight;
  const row = c.lastElementChild, det = row.querySelector('details'), sum = row.querySelector('summary'), res = row.querySelector('.ap-think-content'), txtEl = row.querySelector('.ap-ai-text');
  let fTxt = '', fRes = '', apiMsgs = [{role:"system", content:"You are a helpful assistant."}].concat(s.context?[{role:"user",content:`Context:\n${s.context}`},{role:"assistant",content:"Received."}]:[], s.messages.map(m=>({role:m.role,content:m.content})));

  fetchAI(apiMsgs, document.getElementById(modId).value||cfg.models[0], d => {
    if(d.reasoning_content) { fRes+=d.reasoning_content; det.style.display='block'; res.innerText=fRes; }
    if(d.content) { fTxt+=d.content; txtEl.innerHTML=renderMD(fTxt); if(fRes){ sum.innerText='显示思路 ⌄'; det.removeAttribute('open'); } } c.scrollTop = c.scrollHeight;
  }, () => {
    inp.disabled=false; inp.focus(); s.messages.push({role:'assistant', content:fTxt, reasoning_content:fRes}); saveData();
    row.outerHTML = getMsgHtml(s.messages[s.messages.length-1], sid, s.messages.length-1, cid);
  }, err => { inp.disabled=false; txtEl.innerHTML=`<span style="color:red">${err}</span>`; });
}

const apAsk = () => { apHide(); const s = {id:Date.now().toString(), title:curText.substring(0,15)+'...', context:curText, messages:[], updatedAt:Date.now()}; sessions.unshift(s); saveData(); activePop=s.id; posCard('ap-pop'); document.getElementById('ap-pop-in').value=''; document.getElementById('ap-pop-in').focus(); renderMsgs('ap-pop-msg', s); };

const apTrans = () => {
  apHide(); posCard('ap-trans');
  const c = document.getElementById('ap-trans-res');
  c.innerHTML = '<span style="color:#999">Translating...</span>';
  let fTxt = '';
  fetchAI(
    [
      {role:"system",content:cfg.trans_system_prompt || 'Translate to Chinese. Only output translation.'},
      {role:"user",content:curText}
    ],
    cfg.trans || cfg.models[0],
    d => { if(d.content) { fTxt += d.content; c.innerHTML = renderMD(fTxt); } },
    ()=>{},
    e => c.innerHTML=`<span style="color:red">${e}</span>`
  );
};

const apCapture = () => {
  console.log('[Appine-Debug] 📝 apCapture 函数被触发了！');

  const tplKey = cfg.captureKey || 'c';
  const targetUrl = `org-protocol://capture?template=${tplKey}&url=` + encodeURIComponent(location.href) + '&title=' + encodeURIComponent(document.title) + '&body=' + encodeURIComponent(curText);

  console.log('[Appine-Debug] 🔗 准备跳转的 URL:', targetUrl);

  location.href = targetUrl;
  apHide();
};

export default {
  name: 'selection-assistant',
  async setup(a) {
    api = a;
    await loadData();
    initUI();
    updMods();
    renderActBtns();

    // 拦截事件，防止宿主网页干扰
    clickHandler = e => {
      // 如果点击发生在我们的 UI 内部，立即阻止事件传播给宿主网页
      const inOurUI = ['ap-act','ap-trans','ap-pop','ap-side','ap-set','ap-float'].some(id=>document.getElementById(id)?.contains(e.target));
      if (inOurUI) {
        e.stopPropagation();
      }

      const t = e.target.closest('[data-act]'); if(!t) return;
      e.preventDefault(); // 阻止按钮的默认行为

      const {act, sid, idx, cid, val} = t.dataset;
      console.log('[Appine-Debug] 🖱️ 捕获到按钮点击，动作 (act):', act);
      const acts = {
        trans: apTrans, ask: apAsk, capture: apCapture, hide: apHide, toggleSide: apToggleSide, set: apSet,
        search: () => { window.open(cfg.searchUrl + encodeURIComponent(curText), '_blank'); apHide(); },
        cancelSet: () => document.getElementById('ap-set').style.display='none',
        saveSet: apSaveSet,
        copy: () => navigator.clipboard.writeText(t.closest('.ap-user-row, .ap-ai-row').querySelector('.ap-user-bubble, .ap-ai-text').innerText),
        copyTrans: () => navigator.clipboard.writeText(document.getElementById('ap-trans-res').innerText),
        edit: () => apEdit(sid, parseInt(idx), cid),
        retry: () => apRetry(sid, parseInt(idx), cid),
        more: () => { let m = t.nextElementSibling; m.style.display = m.style.display==='flex'?'none':'flex'; },
        tool: () => alert(val + ' Activated'),
        selSess: () => { activeSide=sid; document.getElementById('ap-side-title').innerText=val; renderList(); renderMsgs('ap-side-msg', sessions.find(x=>x.id===sid)); }
      };
      if(acts[act]) acts[act]();
    };

    // 使用 api.on 注册点击事件 (底层是 window.addEventListener(..., true) 捕获阶段)
    // 这样能抢在 React 之前拿到点击事件
    api.on('click', clickHandler);

    // 为了防止宿主网页在 mousedown 阶段清除选区或关闭弹窗，也拦截 mousedown
    api.on('mousedown', e => {
      if(['ap-act','ap-trans','ap-pop','ap-side','ap-set','ap-float'].some(id=>document.getElementById(id)?.contains(e.target))) {
        e.stopPropagation();
      }
    });
    // 鼠标移入工具条时，取消自动隐藏
    document.getElementById('ap-act')?.addEventListener('mouseenter', () => clearTimeout(hideTimer));

    api.on('mouseup', e => {
      if(['ap-act','ap-trans','ap-pop','ap-side','ap-set','ap-float'].some(id=>document.getElementById(id)?.contains(e.target))) return;
      // 记录鼠标相对于整个文档的坐标
      mouseX = e.pageX;
      mouseY = e.pageY;
      setTimeout(() => {
        const sel = window.getSelection(), t = sel.toString().trim();
        if(t) {
          curText=t; curRect=sel.getRangeAt(0).getBoundingClientRect();
          if(!cfg.key) return apSet();
          apHide(); posCard('ap-act');

          // 3秒后自动隐藏
          clearTimeout(hideTimer);
          hideTimer = setTimeout(() => {
            if (document.getElementById('ap-act').style.display === 'flex') apHide();
          }, 3000);
        } else apHide();
      }, 50);
    });

    ['ap-pop-in','ap-side-in'].forEach(id => document.getElementById(id).addEventListener('keydown', e => { if(e.key==='Enter'&&!e.shiftKey) { e.preventDefault(); handleSend(id==='ap-pop-in'?activePop:activeSide, id==='ap-pop-in'?'ap-pop-msg':'ap-side-msg', id, id==='ap-pop-in'?'ap-pop-mod':'ap-side-mod'); } }));
    api.log('Selection Assistant v0.8 loaded');
  },
  teardown() {
    if(abortCtrl) abortCtrl.abort();
    if(clickHandler) api.off('click', clickHandler); // 记得清理捕获阶段的事件
    ['ap-act','ap-trans','ap-pop','ap-float','ap-side','ap-set','ap-style'].forEach(id=>document.getElementById(id)?.remove());
  }
};
