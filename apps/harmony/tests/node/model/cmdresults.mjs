const { CommandResults, CommandCandidate, CommandEntry, CommandTarget, CommandGroup, CommandVerb, CommandPage, GROUP_LIMIT } =
  await import('../.out/rt/app/CommandResults.ts');
let bad=0; const ok=(c,m)=>{ if(!c){ bad++; console.log('FAIL',m); } };
const E=(t,tg)=>new CommandEntry(t,'',tg);
// 组序 + 空组不显示
const rows=CommandResults.rows([E('规则测试 x',CommandTarget.rule('x.com')),E('设置',CommandTarget.page(CommandPage.SETTINGS)),
  E('流媒体',CommandTarget.scene('s1')),E('规则',CommandTarget.mode('rule'))]);
const gs=CommandResults.groups(rows);
ok(gs.map(g=>g.group).join()===[CommandGroup.COMMAND,CommandGroup.SCENE,CommandGroup.SETTINGS,CommandGroup.RULE_TEST].join(),'order');
ok(rows[3].target.verb===CommandVerb.APPLY&&rows[0].target.verb===CommandVerb.TEST&&rows[1].target.verb===CommandVerb.OPEN,'verbs');
// 5 行上限 + 展开 + key 唯一
const many=CommandResults.rows(Array.from({length:8},(_,i)=>E('n',CommandTarget.nodes('JP',i))).concat([E('n',CommandTarget.nodes('JP',1))]));
ok(new Set(many.map(r=>r.key)).size===9,'unique keys');
const g=CommandResults.groups(many)[0];
ok(CommandResults.shown(g,[]).length===GROUP_LIMIT&&CommandResults.shown(g,[CommandGroup.NODE]).length===9,'limit');
// 前缀匹配
const dis=new CommandCandidate('断开连接','',CommandTarget.toggle(false),['断开','disconnect'],true);
ok(!CommandResults.matches('连接',dis)&&CommandResults.matches('断开',dis)&&CommandResults.matches('dis',dis)&&!CommandResults.matches('d',dis),'prefix');
ok(CommandResults.matches('wi',new CommandCandidate('受信任的 Wi‑Fi','',CommandTarget.page(CommandPage.TRUSTED_WIFI))),'substring');
ok(!CommandResults.matches('  ',dis),'blank');
// 高亮
const keys=['a','b','c'];
ok(CommandResults.moveHighlight(undefined,keys,1,false)==='b','no preview down');
ok(CommandResults.moveHighlight(undefined,keys,1,true)==='a','preview down');
ok(CommandResults.moveHighlight('a',keys,-1,true)===undefined,'preview up');
ok(CommandResults.moveHighlight('a',keys,-1,false)==='a','floor');
ok(CommandResults.moveHighlight('c',keys,1,false)==='c','no wrap');
// 回车
ok(CommandResults.enterRow(gs,[],undefined,false).key===rows[3].key,'enter first');
ok(CommandResults.enterRow(gs,[],undefined,true)===undefined,'enter preview');
ok(CommandResults.enterRow(gs,[],rows[1].key,true).key===rows[1].key,'enter highlighted');
ok(CommandResults.defaultKey(gs,undefined,false)===rows[3].key&&CommandResults.defaultKey(gs,undefined,true)===undefined,'default');
console.log(bad?'FAILED '+bad:'cmdresults OK'); process.exit(bad?1:0);
