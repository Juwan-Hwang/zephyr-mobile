// M1-6 首页背后的纯逻辑：速率曲线环形缓冲 + 几何、全局模式换节点、订阅摘要、故障切换撤销。
const { SparkRing, SparkGeometry, GlobalPick, HomeSubs, Failover, HOME_SUBS_MAX } = await import('../.out/rt/app/HomeModel.ts');
const { MockEngine } = await import('../.out/rt/engine/MockEngine.ts');
let bad = 0; const ok = (c, m) => { if (!c) { bad++; console.log('FAIL', m); } };

const ring = new SparkRing(4);
ring.push(1); ring.push(-5); ring.push(3); ring.push(4); const v = ring.push(5);
ok(v.length === 4 && v[0] === 0 && v[3] === 5, 'ring caps + clamps ' + v);
ok(ring.fill([{ downBps: 9 }, { downBps: 8 }]).join() === '9,8', 'fill');
ring.clear(); ok(ring.values().length === 0, 'clear');

ok(SparkGeometry.build([1], 100, 20) === undefined, 'one point → none');
const g = SparkGeometry.build([0, 5, 10, 5, 0], 100, 20);
ok(g && g.segments.length === 4 && g.start.x === 0 && g.head.x === 100, 'geometry endpoints');
ok(g.segments.every(s => s.c1.y <= 20 && s.c2.y <= 20 && s.to.y >= 0), 'curve stays in box');
ok(SparkGeometry.build([0, 0, 0], 50, 10).segments.every(s => s.to.y === 10), 'flat zero on baseline');

const n = (id, name, ms, protocol = 'vmess') => ({ id, name, protocol, latencyMs: ms });
const nodes = [n(1, 'a', 80), n(2, 'b', 30), n(3, 'c', -1), n(4, 'd', undefined), n(-1, 'DIRECT', 1, 'Direct'), n(5, 'sel', 5, 'Selector')];
ok(GlobalPick.best(nodes, undefined).name === 'b', 'lowest latency');
ok(GlobalPick.best(nodes, n(2, 'b', 30)).name === 'a', 'skip current');
ok(GlobalPick.best([n(3, 'c', -1), n(4, 'd', undefined)], undefined).name === 'd', 'untested beats timeout');
ok(GlobalPick.best([n(5, 'sel', 5, 'URL-Test')], undefined) === undefined, 'groups are not exits');

const subs = Array.from({ length: 5 }, (_, i) => ({ id: 's' + i }));
const hv = HomeSubs.view(subs);
ok(hv.rows.length === HOME_SUBS_MAX && hv.more === 2, 'subs summary');
ok(HomeSubs.view(subs.slice(0, 2)).more === 0, 'no more');

const e = new MockEngine({ latencyScale: 0 });
ok(await e.simulateFailover() === undefined, 'no failover while disconnected');
await e.connect();
let seen; const sub = e.sceneFailovers().subscribe(x => { if (x) seen = x; });
const notice = await e.simulateFailover();
ok(notice && seen && seen.sceneId === notice.sceneId, 'failover emitted');
const scenes = e.scenes().value;
if (notice.switchedTo !== undefined) {
  ok(Failover.canUndo(notice, scenes), 'undo valid right after switch');
  ok(!Failover.canUndo({ ...notice, switchedTo: 'nope' }, scenes), 'undo invalid after manual change');
}
ok(!Failover.canUndo({ sceneId: 'x', sceneName: 'x', failedNode: 'y' }, scenes), 'no target → no undo');
sub.cancel();
console.log(bad ? 'FAILED ' + bad : 'home OK'); process.exit(bad ? 1 : 0);
