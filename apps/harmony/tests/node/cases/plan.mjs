// CommandPlanner × MockEngine：预览 → 应用 → 撤销（契约 §16.d）。
const { CommandPlanner, CommandPlanKind } = await import('../.out/rt/app/CommandPlanner.ts');
const { MockEngine } = await import('../.out/rt/engine/MockEngine.ts');
let bad = 0; const ok = (c, m) => { if (!c) { bad++; console.log('FAIL', m); } };
const e = new MockEngine();
const pl = new CommandPlanner(e);
const ai = () => e.scenes().value.find((s) => s.kind === 'ai');
const video = () => e.scenes().value.find((s) => s.kind === 'video');
// 服务 + 地区：只钉例外
const p1 = await pl.planText('Gemini 走日本');
ok(p1 && p1.kind === CommandPlanKind.EXIT && p1.appId === 'gemini' && p1.regionCode === 'JP' && p1.available > 0 && p1.node.region === 'JP', 'plan gemini jp ' + JSON.stringify(p1 && { k: p1.kind, a: p1.available }));
const sel0 = ai().selected.id;
const pin0 = ai().exceptions.find((x) => x.appId === 'gemini')?.node.id;
const undo1 = await pl.apply(p1);
ok(ai().exceptions.find((x) => x.appId === 'gemini')?.node.id === p1.node.id, 'gemini pinned');
ok(ai().selected.id === sel0, 'scene selected unchanged');
await undo1();
ok(ai().exceptions.find((x) => x.appId === 'gemini')?.node.id === pin0, 'gemini pin restored');
// 场景词 + 地区：整场景
const p2 = await pl.planText('视频走日本');
ok(p2 && p2.kind === CommandPlanKind.EXIT && p2.isSceneWord, 'plan video scene');
const v0 = video().selected.id;
const undo2 = await pl.apply(p2);
ok(video().selected.id === p2.node.id, 'video switched');
await undo2();
ok(video().selected.id === v0, 'video restored');
// 直连
const p3 = await pl.planText('GitHub 直连');
ok(p3 && p3.kind === CommandPlanKind.DIRECT && p3.host === 'github.com', 'plan direct');
const undo3 = await pl.apply(p3); await undo3();
// 收窄
ok((await pl.planText('Gemini 直连')) === undefined, 'ai direct: no card');
ok((await pl.planText('GitHub 走日本')) === undefined, 'other + region: no card');
ok((await pl.planText('香港')) === undefined, 'region only: no plan');
ok(CommandPlanner.looksLikeHost('github.com') && CommandPlanner.looksLikeHost('1.1.1.1') && !CommandPlanner.looksLikeHost('香港') && !CommandPlanner.looksLikeHost('Gemini 走日本'), 'looksLikeHost');
// 4K（§15.h）：mock 池没有 4K 节点 → 不可用
const u0 = await pl.planText('视频只用 4K 节点');
ok(u0 && u0.kind === CommandPlanKind.UHD && !u0.clear && u0.unavailable && !u0.applicable && u0.preview && u0.preview.poolMatching === 0, 'uhd unavailable ' + JSON.stringify(u0 && u0.preview));
ok((await pl.planText('Gemini 4K')) === undefined, 'uhd only for video');
let thr; try { await e.setSceneNodeFilter('video', 'uhd'); } catch (x) { thr = x.code; } ok(thr === 'rule_input_invalid', 'mock set uhd throws');
await e.setSceneNodeFilter('video', undefined); ok(video().nodeFilter === undefined, 'clear ok');
// 有 4K 节点（替身 preview / set）：当前不是 4K → 一并切到 suggested；撤销恢复过滤与节点
const jp = (await e.sceneCandidates('video', 'JP'))[0]; const sug = { ...jp, name: jp.name + ' 4K' };
const real = e.setSceneNodeFilter.bind(e);
e.previewSceneNodeFilter = async () => ({ matching: 3, total: 9, poolMatching: 5, currentKept: false, suggested: sug, change: await e.previewSceneChange('video', sug.id) });
e.setSceneNodeFilter = async (sid, f) => { e.sceneState.value = e.sceneState.value.map((s) => s.id === sid ? { ...s, nodeFilter: f } : s); };
const u1 = await pl.planText('视频只用 4K 节点');
ok(u1 && u1.applicable && u1.uhdTarget && u1.uhdTarget.id === sug.id && u1.change && u1.change.toRegion === 'JP', 'uhd switch plan');
const vs = video().selected.id;
const undoU = await pl.apply(u1);
ok(video().nodeFilter === 'uhd' && video().selected.id === sug.id, 'uhd applied + switched');
await undoU();
ok(video().nodeFilter === undefined && video().selected.id === vs, 'uhd undo');
await e.setSceneNodeFilter('video', 'uhd');
const u2 = await pl.planText('视频只用 4K 节点');
ok(u2 && u2.kind === CommandPlanKind.UHD && u2.clear && u2.applicable && u2.uhdTarget === undefined, 'uhd clear plan');
const undo2u = await pl.apply(u2); ok(video().nodeFilter === undefined, 'uhd cleared'); await undo2u(); ok(video().nodeFilter === 'uhd', 'uhd clear undo');
e.previewSceneNodeFilter = async () => ({ matching: 3, total: 9, poolMatching: 5, currentKept: true });
await e.setSceneNodeFilter('video', undefined);
const u3 = await pl.planText('视频只用 4K 节点'); ok(u3 && u3.applicable && u3.uhdTarget === undefined && u3.change === undefined, 'uhd keep');
void real;
console.log(bad ? `plan FAIL ${bad}` : 'plan ok');
process.exit(bad ? 1 : 0);
