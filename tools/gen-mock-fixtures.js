// 从原型 design/prototype/pages.js 直接求值，生成 MockEngine 校验样本。两端单测必须与之逐项一致。
const fs=require('fs'),vm=require('vm'),path=require('path');
const src=fs.readFileSync(path.join(__dirname,'../design/prototype/pages.js'),'utf8');
const ctx={performance:{now:()=>0},document:{},window:{},console,Map,Set,Math,String,Number};
const stub=new Proxy(function(){},{get:(t,k)=>k===Symbol.toPrimitive?()=>0:(k==='length'?0:stub),apply:()=>stub,construct:()=>stub,set:()=>true});
ctx.$=()=>stub;ctx.$$=()=>[];ctx.document=stub;ctx.window=stub;ctx.requestAnimationFrame=()=>0;ctx.setTimeout=()=>0;ctx.clearTimeout=()=>0;ctx.addEventListener=()=>0;
vm.createContext(ctx);
vm.runInContext(src+'\n;globalThis.__x={RG,NTOT,TAGS,PROT,tagOf,protOf,hsh,carOf,MULT,nodeName,cachedLat,buildModel,rowAt,LAYERS,RTOT,matchRule,get G(){return G},get GT(){return GT}};',ctx);
const X=ctx.__x;
const out={generator:'design/prototype/pages.js',total:X.NTOT,regions:X.RG.map((g,i)=>({index:i,code:g[0],name:g[1],count:g[2],cities:g[3],baseLatency:g[4],carriers:g[5]})),tags:X.TAGS,protocols:X.PROT};
// 节点样本
const samples=[];const idx=[0,1,2,3,4,5,9,10,63,64,99,320,321,999,1234,65535,100000,999999,1906550];
X.RG.forEach((g,r)=>idx.filter(j=>j<g[2]).concat([g[2]-1]).forEach(j=>{
  const lat=X.cachedLat(r,j);samples.push({id:r*1e8+j,region:r,index:j,name:X.nodeName(r,j),tag:X.TAGS[X.tagOf(r,j)],protocol:X.PROT[X.protOf(r,j)],carrier:g[5][X.carOf(r,j)],city:g[3][j%g[3].length],hash:X.hsh(r,j),cachedLatency:lat});
}));
out.nodes=samples;
// 查询样本
const qs=['','jp','日本','东京','ntt','iplc','东京 iplc','us 家宽','hkt','香港 hkt bgp','ip','zzz','新加坡','cn2 gia','tw hinet 原生','美国 洛杉矶'];
out.queries=qs.map(q=>{const m=X.buildModel(q);const G=X.G;const rows=[];
  for(let k=0;k<Math.min(X.GT,12);k++){const a=X.rowAt(k);rows.push(a.h?{header:X.RG[a.g.r][0]}:{id:a.g.r*1e8+a.j,name:X.nodeName(a.g.r,a.j)});}
  return {query:q,total:m.n,sections:G.map(g=>({region:X.RG[g.r][0],count:g.count})),firstRows:rows};});
out.rules={layers:X.LAYERS.map((l,i)=>({index:i,kind:l[0],name:l[1],count:l[2],note:l[3]})),total:X.RTOT,
  tests:['github.com','api.github.com','netflix.com','chatgpt.com','claude.ai','doubleclick.net','ads.example.com','malware-test.com','baidu.com','example.cn','36.1.2.3','8.8.8.8','example.org'].map(q=>{const m=X.matchRule(q);return {input:q,layerIndex:m.hit?m.hit[0]:null,rule:m.hit?m.hit[2]:'MATCH',ruleNo:m.hit?m.hit[3]:null,policy:m.hit?m.hit[4]:'O'};})};
fs.writeFileSync(path.join(__dirname,'../contract/fixtures/mock-v0.json'),JSON.stringify(out,null,1));
console.log('total',out.total,'nodes',samples.length,'queries',out.queries.map(q=>q.query+':'+q.total).join(' | '));
