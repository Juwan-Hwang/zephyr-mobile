// 订阅删除 → 撤销流程（UndoableDelete × ToastCenter × MockEngine）
const { ToastCenter } = await import('../.out/rt/app/ToastCenter.ts');
const { UndoableDelete } = await import('../.out/rt/app/UndoableDelete.ts');
const { MockEngine } = await import('../.out/rt/engine/MockEngine.ts');
class FT{constructor(){this.now=0;this.seq=0;this.m=new Map()}set(cb,ms){this.m.set(++this.seq,[this.now+ms,cb]);return this.seq}clear(id){this.m.delete(id)}adv(ms){this.now+=ms;for(const [id,[at,cb]] of [...this.m]){if(at<=this.now){this.m.delete(id);cb()}}}}
let bad=0;const ok=(c,m)=>{if(!c){bad++;console.log('FAIL',m)}};
const tick=()=>new Promise(r=>setTimeout(r,5));
const e=new MockEngine({latencyScale:0});const n=e.subscriptions().value.length;ok(n>=2,'subs '+n);
const t=new FT(),c=new ToastCenter(()=>false,t);const ev=[];c.onEvent=(a,s,d)=>ev.push(a+':'+d);
let hidden=[];const run=(s)=>UndoableDelete.run(c,{message:'x',hide:()=>hidden.push(s.id),unhide:()=>{hidden=hidden.filter(x=>x!==s.id)},commit:()=>e.deleteSubscription(s.id),onError:()=>{}});
const a=e.subscriptions().value[0];run(a);ok(hidden.length===1,'hidden');ok(c.undoCurrent(),'undo');t.adv(9e4);await tick();ok(e.subscriptions().value.length===n&&hidden.length===0,'undo keeps');
ok(!c.undoCurrent()&&ev.at(-1)==='undo_missed:no pending toast','missed '+ev);
run(a);t.adv(5000);await tick();ok(e.subscriptions().value.length===n-1&&hidden.length===0,'timeout deletes');ok(ev.includes('commit:timeout'),'reason');
console.log(bad?'undo FAIL':'undo ok');process.exit(bad?1:0);
