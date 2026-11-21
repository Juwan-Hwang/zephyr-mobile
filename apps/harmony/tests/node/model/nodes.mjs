const { MockEngine } = await import('../.out/rt/engine/MockEngine.ts');
const { NodeListModel, NodeRowSource, NODE_PAGE } = await import('../.out/rt/app/NodeListModel.ts');
let bad=0; const ok=(c,m)=>{ if(!c){bad++;console.log('FAIL',m);} };
const e=new MockEngine({latencyScale:0});
const m=new NodeListModel(e); let resets=0, changed=[]; m.onReset=()=>resets++; m.onRowChanged=r=>changed.push(r);
m.start(); await m.query('');
const st=m.state(); ok(st.total>1000 && resets===1,'query '+JSON.stringify({t:st.total,s:st.sections}));
ok(m.rowCount()===st.total+st.sections,'rowCount');
const src=new NodeRowSource(m); ok(src.totalCount()===m.rowCount(),'src');
ok(m.item(0).kind==='header','row0 header');
m.setVisible(0,20);
const it=m.item(1); ok(it.kind==='node' && it.node===undefined && it.ordinal===0,'skeleton first');
await new Promise(r=>setTimeout(r,5));
ok(changed.includes(1),'page notified');
const it2=m.item(1); ok(it2.node!==undefined && it2.key!==it.key,'loaded '+it2.key);
// section 2 header & ordinal mapping
const res=await e.queryNodes(''); const s1=res.sections[1];
await m.query(''); const h=m.item(s1.rowOffset); ok(h.kind==='header'&&h.section.region===s1.region,'2nd header');
const n=m.item(s1.rowOffset+1); ok(n.ordinal===res.sections[0].count,'ordinal after first section '+n.ordinal);
ok(m.ordinalToRow(n.ordinal)===s1.rowOffset+1,'rowOf');
// latency test
m.setVisible(0,20); m.item(1); await new Promise(r=>setTimeout(r,5));
const ids=m.visibleIds(); ok(ids.length>0,'visible ids '+ids.length);
changed=[]; m.test(ids.slice(0,3)); ok(m.item(1).testing||changed.length>0,'testing marked');
await new Promise(r=>setTimeout(r,50)); ok(m.latencyOf(ids[0])!==undefined,'latency arrived');
await m.query('zzzzqqq'); ok(m.rowCount()===0||m.state().total===0,'no match '+m.state().total);
m.dispose(); console.log(bad?'FAILED '+bad:'nodes OK'); process.exit(bad?1:0);
