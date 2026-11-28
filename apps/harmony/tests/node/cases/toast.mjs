const { ToastCenter } = await import('../.out/rt/app/ToastCenter.ts');
class FT{constructor(){this.now=0;this.seq=0;this.m=new Map()}set(cb,ms){this.m.set(++this.seq,[this.now+ms,cb]);return this.seq}clear(id){this.m.delete(id)}adv(ms){this.now+=ms;for(const [id,[at,cb]] of [...this.m]){if(at<=this.now){this.m.delete(id);cb()}}}}
let bad=0;const ok=(c,m)=>{if(!c){bad++;console.log('FAIL',m)}};
let t=new FT(),c=new ToastCenter(()=>false,t),log=[];
c.show('d',{onUndo:()=>log.push('undo'),onCommit:()=>log.push('commit')});ok(t.m.size===1,'armed');
ok(c.undoCurrent(),'ran');ok(t.m.size===0,'timer cleared');t.adv(60000);ok(JSON.stringify(log)==='["undo"]','only undo '+log);ok(!c.undoCurrent(),'second');
t=new FT();c=new ToastCenter(()=>false,t);log=[];const a=c.show('a',{onUndo:()=>log.push('ua'),onCommit:()=>log.push('ca')});c.show('b',{onUndo:()=>log.push('ub'),onCommit:()=>log.push('cb')});c.undo(a);ok(c.undoCurrent(),'cur');t.adv(9e4);ok(JSON.stringify(log)==='["ca","ub"]','stale '+log);
console.log(bad?'toast FAIL':'toast ok');process.exit(bad?1:0);
