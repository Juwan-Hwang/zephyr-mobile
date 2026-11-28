const { CardSnapshots, CardSnapshot, CardScene, CARD_SCENE_ROWS } = await import('../.out/rt/widget/CardSnapshot.ts');
let bad=0; const ok=(c,m)=>{ if(!c){ bad++; console.log('FAIL',m); } };
const s=new CardSnapshot(); s.on=true; s.title='已连接'; s.today='今日 1.2 GB'; s.todayZero='今日 0 B';
s.day=CardSnapshots.dayKey(Date.UTC(2026,10,22,4)); for(let i=0;i<5;i++){const c=new CardScene();c.name='s'+i;s.scenes.push(c);}
const back=CardSnapshots.decode(CardSnapshots.encode(s));
ok(back.on&&back.title==='已连接'&&back.scenes.length===CARD_SCENE_ROWS,'roundtrip caps scenes');
ok(CardSnapshots.decode('{bad').title==='Zephyr'&&!CardSnapshots.decode(undefined).on,'bad file -> default');
const same=CardSnapshots.forDisplay(back,Date.UTC(2026,10,22,5));
ok(same.today==='今日 1.2 GB','same day keeps today');
const next=CardSnapshots.forDisplay(back,Date.UTC(2026,10,24,5));
ok(next.today==='今日 0 B'&&back.today==='今日 1.2 GB','midnight resets today, original untouched');
const b=CardSnapshots.binding(back,true); ok(b.wide===true&&b.on===true&&Array.isArray(b.scenes),'binding');
let ids=CardSnapshots.withId([], '1', false); ids=CardSnapshots.withId(ids,'2',true); ids=CardSnapshots.withId(ids,'1',true);
ok(ids.length===2&&CardSnapshots.wideOf(ids,'1')&&CardSnapshots.wideOf(ids,'2')&&!CardSnapshots.wideOf(ids,'3'),'ids wide');
ids=CardSnapshots.withoutId(ids,'1'); ok(ids.length===1&&CardSnapshots.idOf(ids[0])==='2','remove');
ok(CardSnapshots.decodeIds('["a#s","a#s",3]').length===1&&CardSnapshots.decodeIds('x').length===0,'decode ids');
console.log(bad?'FAILED '+bad:'cardsnap OK'); process.exit(bad?1:0);
