/* ---------- library pages ---------- */
const fmt=n=>n.toLocaleString('en-US');
const RG=[
 ['US','美国',3118402,['洛杉矶','圣何塞','西雅图','纽约','达拉斯'],152,['CN2 GIA','Cogent','Zenlayer','HE']],
 ['JP','日本',2204117,['东京','大阪'],58,['NTT','IIJ','KDDI','SoftBank']],
 ['HK','香港',1906551,['香港'],34,['HKT','HKBN','PCCW','CMI']],
 ['SG','新加坡',1512880,['新加坡'],63,['Akari','SingTel','StarHub']],
 ['TW','台湾',1288406,['台北','台中'],41,['HiNet','Seednet','So-net']],
 ['KR','韩国',702315,['首尔','春川'],69,['KT','SK','LG U+']],
 ['DE','德国',488210,['法兰克福','柏林'],204,['Hetzner','DTAG']],
 ['GB','英国',455903,['伦敦','曼彻斯特'],218,['BT','Vultr']],
 ['NL','荷兰',301442,['阿姆斯特丹'],226,['KPN','Leaseweb']],
 ['FR','法国',254118,['巴黎'],231,['OVH','Orange']],
 ['CA','加拿大',239770,['多伦多','温哥华'],171,['Bell','Rogers']],
 ['AU','澳大利亚',214906,['悉尼'],139,['Telstra','Optus']],
 ['IN','印度',198331,['孟买'],118,['Jio','Airtel']],
 ['BR','巴西',126004,['圣保罗'],301,['Vivo','Claro']],
 ['TR','土耳其',98447,['伊斯坦布尔'],246,['Türk Telekom']]];
const NTOT=RG.reduce((a,r)=>a+r[2],0);
const TAGS=['IPLC','IEPL','BGP','家宽','原生'],PROT=['VLESS','Hy2','TUIC','SS','Trojan'];
const tagOf=(r,j)=>(j*7+r)%5, protOf=(r,j)=>hsh(r+7,j)%5;
const hsh=(r,j)=>{let h=(j*2654435761+r*97)>>>0;h^=h>>>15;h=Math.imul(h,2246822519)>>>0;h^=h>>>13;return h>>>0;};
const carOf=(r,j)=>Math.floor(j/5)%RG[r][5].length;
const MULT=['','','','',' ×1.5','','',' ×0.5','',' ×2'];
const gcd=(a,b)=>b?gcd(b,a%b):a,lcm=(a,b)=>a/gcd(a,b)*b;
const nodeName=(r,j)=>{const g=RG[r],c=g[3],n=(Math.floor(j/lcm(c.length,5*g[5].length))%64)+1;return `${c[j%c.length]} ${g[5][carOf(r,j)]} ${TAGS[tagOf(r,j)]} ${String(n).padStart(2,'0')}${MULT[hsh(r+3,j)%10]}`;};
const LAT=new Map();let tested=0;
function cachedLat(r,j){const k=r*1e8+j;if(LAT.has(k))return LAT.get(k);const h=hsh(r,j);if(h%11<3){const v=RG[r][4]+h%37;return v;}return null;}

/* model: groups of {r,count,S,P} — rows: header + matching nodes */
let G=[],GS=[],GT=0,hl=[];
function buildModel(q){
  const t0=performance.now();
  const toks=q.trim().toLowerCase().split(/\s+/).filter(Boolean);
  let regs=null,cityTok=null,tag=null,prot=null,car=null,ok=true;hl=[];
  const meet=s=>{regs=regs?new Set([...regs].filter(x=>s.has(x))):s;};
  toks.forEach((tk,ti0)=>{const last=ti0===toks.length-1;
    let s=new Set();
    RG.forEach((g,ri)=>{if(g[0].toLowerCase()===tk||g[1].includes(tk)||tk.includes(g[1]))s.add(ri);});
    if(s.size){meet(s);hl.push(tk);return;}
    RG.forEach((g,ri)=>{g[3].forEach((c,ci)=>{if(c.includes(tk)||tk.includes(c)){s.add(ri);(cityTok=cityTok||{})[ri]=ci;hl.push(c);}});});
    if(s.size){meet(s);return;}
    RG.forEach((g,ri)=>{const ci=g[5].findIndex(x=>{const l=x.toLowerCase();return l===tk||l.replace(/\s/g,'')===tk||l.split(/\s+/).includes(tk)||(tk.length>=2&&l.startsWith(tk));});if(ci>=0){s.add(ri);(car=car||{})[ri]=ci;hl.push(g[5][ci]);}});
    if(s.size){meet(s);return;}
    const ti=TAGS.findIndex(x=>x.toLowerCase()===tk||(tk.length>=2&&x.toLowerCase().startsWith(tk)));if(ti>=0){tag=ti;hl.push(TAGS[ti]);return;}
    if(last&&/^[a-z0-9+-]{1,3}$/.test(tk))return;ok=false;
  });
  G=[];
  if(ok)RG.forEach((g,ri)=>{
    if(regs&&!regs.has(ri))return;
    const L=g[3].length,C=g[5].length,hasC=car&&car[ri]!=null,hasT=cityTok&&cityTok[ri]!=null;
    const P=(hasT?L:1)*((tag!=null||hasC)?5:1)*(hasC?C:1)||1,S=[];
    for(let j=0;j<P;j++){
      if(cityTok&&cityTok[ri]!=null&&j%L!==cityTok[ri])continue;
      if(tag!=null&&tagOf(ri,j)!==tag)continue;
      if(prot!=null&&protOf(ri,j)!==prot)continue;
      if(hasC&&carOf(ri,j)!==car[ri])continue;S.push(j);}
    let cnt=0;S.forEach(s=>{if(s<g[2])cnt+=Math.floor((g[2]-1-s)/P)+1;});
    if(cnt)G.push({r:ri,count:cnt,S,P});
  });
  GS=[];GT=0;let nn=0;G.forEach(g=>{GS.push(GT);GT+=1+g.count;nn+=g.count;});
  return {n:nn,ms:performance.now()-t0,q:toks.length>0};
}
function rowAt(row){
  let lo=0,hi=G.length-1;while(lo<hi){const m=(lo+hi+1)>>1;if(GS[m]<=row)lo=m;else hi=m-1;}
  const g=G[lo],k=row-GS[lo];if(k===0)return{h:1,gi:lo,g};
  const kk=k-1,j=Math.floor(kk/g.S.length)*g.P+g.S[kk%g.S.length];return{h:0,gi:lo,g,j,k:kk};
}
let RH=52;let vOff=0,vVel=0,vDrag=false,vRaf=0,idleT=0,vPool=[];
const vl=()=>$('#vl');
function vh(){return vl().clientHeight;}
function clampOff(){const max=Math.max(0,GT-(vh()-70)/RH);vOff=Math.max(0,Math.min(max,vOff));}
function hEsc(s){return s.replace(/[&<>]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]));}
function mark(name){let s=hEsc(name);hl.forEach(t=>{const i=s.toLowerCase().indexOf(t.toLowerCase());if(i>=0)s=s.slice(0,i)+'<em>'+s.slice(i,i+t.length)+'</em>'+s.slice(i+t.length);});return s;}
function renderV(){
  const box=$('#vrows');if(!box)return;
  const n=Math.ceil(vh()/RH)+2;
  while(vPool.length<n){const d=document.createElement('div');d.className='vr';box.appendChild(d);vPool.push(d);}
  if(!GT){vPool.forEach(d=>d.style.display='none');$('#vpin').style.display='none';$('#vpos').textContent='';return;}
  const first=Math.floor(vOff),frac=vOff-first;
  let firstNode=null;
  for(let i=0;i<vPool.length;i++){
    const d=vPool[i],row=first+i;
    if(i>=n||row>=GT){d.style.display='none';continue;}
    d.style.display='';d.style.transform=`translateY(${(i-frac)*RH}px)`;
    const a=rowAt(row),g=RG[a.g.r];
    if(a.h){d.className='vr hd';d.innerHTML=`<span class="cc">${g[0]}</span><b>${g[1]}</b><span class="c2 num">${fmt(a.g.count)}</span>`;}
    else{
      if(firstNode==null)firstNode=a;
      const key=a.g.r*1e8+a.j,lat=LAT.has(key)?LAT.get(key):cachedLat(a.g.r,a.j);
      const ms=lat==null?'<span class="ms u">—</span>':lat==='…'?'<span class="ms u">···</span>':`<span class="ms${lat>200?' w':''}">${lat} ms</span>`;
      d.className='vr';d.dataset.k=key;d.innerHTML=`<span class="nm">${mark(nodeName(a.g.r,a.j)).replace(/ (×[\d.]+)$/,' <span class="mx">$1</span>')}</span><span class="pr">${PROT[protOf(a.g.r,a.j)]}</span>${ms}`;
    }
  }
  const top=rowAt(Math.min(GT-1,Math.max(0,Math.floor(vOff+0.75))));
  const pg=RG[top.g.r];
  $('#vpin').style.display=GT&&vOff>0.5?'':'none';
  $('#vpin').innerHTML=`<span class="cc">${pg[0]}</span><b>${pg[1]}</b><span class="c2 num">${fmt(top.g.count)}</span>`;
  if(firstNode){
    let idx=0;for(let i=0;i<firstNode.gi;i++)idx+=G[i].count;idx+=firstNode.k+1;
    const tot=G.reduce((a,g)=>a+g.count,0);
    $('#vpos').textContent=`${fmt(idx)} / ${fmt(tot)}`;
  } else $('#vpos').textContent='';
  $('#vtest').textContent=`已检测 ${fmt(41280+tested)}`;
}
function settle(){
  clearTimeout(idleT);
  idleT=setTimeout(()=>{
    vPool.forEach(d=>{
      if(d.style.display==='none'||!d.dataset.k||d.classList.contains('hd'))return;
      const k=+d.dataset.k,r=Math.floor(k/1e8),j=k%1e8;
      if(LAT.has(k)||cachedLat(r,j)!=null)return;
      LAT.set(k,'…');
      setTimeout(()=>{const h=hsh(r,j);LAT.set(k,h%13===0?RG[r][4]+180+h%90:RG[r][4]+h%41);tested++;renderV();},250+hsh(j,r)%700);
    });renderV();
  },420);
}
function tick(){
  if(!vDrag&&Math.abs(vVel)>0.002){vOff+=vVel;vVel*=0.95;clampOff();renderV();vRaf=requestAnimationFrame(tick);}
  else{vRaf=0;if(!vDrag)settle();}
}
function initVL(){
  const el=vl();if(!el||el.dataset.init)return;el.dataset.init=1;
  el.addEventListener('wheel',e=>{e.preventDefault();vOff+=e.deltaY/RH;clampOff();renderV();settle();},{passive:false});
  let ly=0,lt=0;
  el.addEventListener('pointerdown',e=>{if(e.target.closest('#rail'))return;vDrag=true;vVel=0;ly=e.clientY;lt=performance.now();el.setPointerCapture(e.pointerId);});
  el.addEventListener('pointermove',e=>{if(!vDrag)return;const dy=e.clientY-ly,now=performance.now();vOff-=dy/RH;vVel=-(dy/RH)/Math.max(1,(now-lt)/16);ly=e.clientY;lt=now;clampOff();renderV();});
  el.addEventListener('pointerup',()=>{vDrag=false;if(!vRaf)vRaf=requestAnimationFrame(tick);});
  // rail
  const rail=$('#rail');
  const railAt=e=>{const b=rail.getBoundingClientRect(),f=Math.max(0,Math.min(.999,(e.clientY-b.top)/b.height));
    const gi=Math.floor(f*G.length),g=G[gi];if(!g)return;
    const within=(f*G.length-gi);vOff=GS[gi]+Math.floor(within*g.count);clampOff();vVel=0;renderV();
    const r=RG[g.r];$('#bubT').textContent=r[0]+' '+r[1];$('#bubS').textContent=fmt(Math.floor(within*g.count)+1)+' / '+fmt(g.count);
    $('#bub').style.top=(e.clientY-el.getBoundingClientRect().top-32)+'px';$('#bub').classList.add('show');};
  let rd=false;
  rail.addEventListener('pointerdown',e=>{rd=true;rail.setPointerCapture(e.pointerId);railAt(e);});
  rail.addEventListener('pointermove',e=>{if(rd)railAt(e);});
  rail.addEventListener('pointerup',()=>{rd=false;setTimeout(()=>$('#bub').classList.remove('show'),500);settle();});
}
function applyQuery(q){
  const res=buildModel(q);vOff=0;vVel=0;
  $('#nfs').classList.toggle('has',!!q);
  $('#ntm').textContent=res.q?`${fmt(res.n)} 个 · ${res.ms<1?res.ms.toFixed(2):res.ms.toFixed(1)} ms`:'';
  $('#vempty').style.display=res.n?'none':'flex';$('#vemptyS').textContent=`没有与“${q.trim()}”匹配的节点`;
  $('#rail').innerHTML=G.map(g=>`<span>${RG[g.r][0]}</span>`).join('');
  $('#rail').style.display=G.length>1?'':'none';
  $$('#nchips .chip').forEach(c=>c.classList.toggle('on',(c.dataset.q||'')===q.trim()));
  renderV();settle();
}
function openNodes(q=''){
  show('nodes');RH=dev.classList.contains('xl')?66:52;vPool.forEach(d=>d.style.height=RH+'px');initVL();
  $('#nTotal').textContent=fmt(NTOT);$('#nSub').textContent=`来自 214 个订阅 · ${RG.length} 个地区`;
  $('#nchips').innerHTML=`<button class="chip" data-q="">全部</button>`+RG.slice(0,8).map(r=>`<button class="chip" data-q="${r[0]}">${r[0]} <i>${(r[2]/1e4).toFixed(0)} 万</i></button>`).join('');
  $$('#nchips .chip').forEach(c=>c.onclick=()=>{$('#nq').value=c.dataset.q;applyQuery(c.dataset.q);});
  $('#nq').value=q;requestAnimationFrame(()=>applyQuery(q));
}

/* rules */
const LAYERS=[
 ['覆写','Zephyr 覆写',14,'在订阅之上'],
 ['订阅','Nebula Cloud',1284,'订阅规则'],
 ['域名','OpenAI',312,'规则集 · 每天更新'],
 ['域名','广告与跟踪',61204113,'规则集 · 每天更新'],
 ['域名','威胁情报',33481790,'规则集 · 每小时更新'],
 ['域名','geosite:cn',8912004,'规则集 · 每周更新'],
 ['IP','geoip:cn',7214,'规则集 · 每周更新']];
const RTOT=LAYERS.reduce((a,l)=>a+l[2],0);
const POL={AI:['AI','SG','新加坡 02','198.51.100.7'],V:['视频','HK','香港 HKT','203.0.113.24'],O:['其他','TW','TW-Fixed-01','198.51.100.41']};
function matchRule(q){
  q=q.trim().toLowerCase();if(!q)return null;
  const ip=/^\d+\.\d+\.\d+\.\d+$/.test(q);
  const T=[
    [0,/(^|\.)github\.com$/,'DOMAIN-SUFFIX,github.com',2,'DIRECT'],
    [1,/(^|\.)netflix\.com$|(^|\.)nflxvideo\.net$/,'DOMAIN-SUFFIX,netflix.com',318,'V'],
    [2,/(^|\.)openai\.com$|(^|\.)chatgpt\.com$|(^|\.)claude\.ai$|(^|\.)anthropic\.com$/,'DOMAIN-SUFFIX,'+q.split('.').slice(-2).join('.'),41,'AI'],
    [3,/doubleclick|adservice|(^|\.)ads?\.|tracker|analytics/,'DOMAIN-KEYWORD,'+(q.match(/doubleclick|adservice|ads?|tracker|analytics/)||['ad'])[0],18204451,'REJECT'],
    [4,/malware|phish/,'DOMAIN,'+q,2201833,'REJECT'],
    [5,/(^|\.)(baidu|qq|taobao|bilibili|weibo|jd)\.com$|\.cn$/,'DOMAIN-SUFFIX,'+q.split('.').slice(-2).join('.'),1120458,'DIRECT'],
    [6,/^(1\.0\.|36\.|58\.|101\.|110\.|111\.|112\.|113\.|114\.|115\.|116\.|117\.|118\.|119\.|120\.|121\.|122\.|123\.|124\.|125\.)/,'IP-CIDR,'+q.split('.').slice(0,2).join('.')+'.0.0/16',3302,'DIRECT']];
  const t0=performance.now();let hit=null;
  for(const r of T){if(ip!==(r[0]===6))continue;if(r[1].test(q)){hit=r;break;}}
  const ms=performance.now()-t0+0.01+q.length*0.0007;
  return {q,hit,ms};
}
function renderRules(){
  $('#rTotal').textContent=fmt(RTOT);
  const m=matchRule($('#rq').value);$('#rfs').classList.toggle('has',!!$('#rq').value);
  $('#layers').innerHTML=LAYERS.map((l,i)=>`<div class="gr${m&&m.hit&&m.hit[0]===i?' hit':''}"><span class="ix num">${i+1}</span><div class="tx"><b>${l[1]}</b><small>${l[3]}</small></div><span class="tg${i===0?' b':''}">${l[0]}</span><span class="n">${fmt(l[2])}</span></div>`).join('')+
    `<div class="gr${m&&!m.hit?' hit':''}"><span class="ix num">8</span><div class="tx"><b>其余流量</b><small>MATCH</small></div><span class="n" style="color:var(--t3)">其他</span></div>`;
  if(!m){$('#chain').innerHTML='<div style="font-size:13px;color:var(--t3);padding:4px 0">输入域名或 IP，查看匹配的规则与出口。</div>';return;}
  const st=(s,b,mono,em)=>`<div class="st"><i></i><div><small>${s}</small><b${mono?' class="m"':''}>${b}</b></div>${em?`<em>${em}</em>`:''}</div>`;
  let h=st('请求',hEsc(m.q),1);
  if(m.hit){const L=LAYERS[m.hit[0]];h+=st(`第 ${m.hit[0]+1} 层 · ${L[1]}`,hEsc(m.hit[2]),1,'#'+fmt(m.hit[3]));
    const p=m.hit[4];
    if(p==='DIRECT')h+=st('出口','直连');else if(p==='REJECT')h+=st('结果','已拦截');
    else{const P=POL[p];h+=st('场景 · '+P[0],`<span class="cc" style="margin-right:6px">${P[1]}</span>${P[2]}`)+st('出口 IP',P[3],1);}
  } else {const P=POL.O;h+=st('第 8 层 · 其余流量','MATCH',1)+st('场景 · 其他',`<span class="cc" style="margin-right:6px">${P[1]}</span>${P[2]}`)+st('出口 IP',P[3],1);}
  h+=`<div class="tm2">用时 ${m.ms.toFixed(2)} ms</div>`;
  $('#chain').innerHTML=h;
}
function openRules(q){show('rules');if(q!=null)$('#rq').value=q;renderRules();}
$('#rq').addEventListener('input',renderRules);
$('#rx').onclick=()=>{$('#rq').value='';renderRules();$('#rq').focus();};
$('#nq').addEventListener('input',e=>applyQuery(e.target.value));
$('#nx').onclick=()=>{$('#nq').value='';applyQuery('');};
$$('[data-back]').forEach(b=>b.onclick=()=>{show('home');sheet('libSheet');});
$$('#libSheet .lc').forEach((b,i)=>b.onclick=()=>{closeSheets(true);[()=>openNodes(),()=>show('subs'),()=>openRules(),()=>openScene&&openScene()][i]();});
$$('#libSheet .li').forEach(b=>{if(b.textContent.includes('设置'))b.onclick=()=>{closeSheets(true);show('settings');};});
window.addEventListener('resize',()=>{if(!$('#nodes').classList.contains('off'))renderV();});

{const gb=$('.home .top .ibtn[aria-label="设置"]');if(gb)gb.onclick=()=>show('settings');}
