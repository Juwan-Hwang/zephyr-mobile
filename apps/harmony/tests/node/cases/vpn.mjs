import fs from 'node:fs';
import os from 'node:os';
const { LanBypass } = await import('../.out/rt/vpn/LanBypass.ts');
const { StartIntentStore, VpnStatusStore, VpnPhase } = await import('../.out/rt/vpn/StartIntent.ts');
const { TunBridges, SimulatedTunBridge, NativeTunBridge } = await import('../.out/rt/vpn/TunBridge.ts');
const { buildVpnConfig } = await import('../.out/rt/vpn/VpnConfigBuilder.ts');
let bad = 0; const ok = (c, m) => { if (!c) { bad++; console.log('FAIL', m); } };
// complement tables = 0/0 minus excluded (v4 via integer ranges)
const ip = (s) => s.split('.').reduce((a, b) => a * 256 + +b, 0);
const rng = (c) => { const [a, l] = c.split('/'); const s = ip(a); return [s, s + 2 ** (32 - +l) - 1]; };
const ex = LanBypass.V4_EXCLUDED.map(rng).sort((a, b) => a[0] - b[0]);
const rs = LanBypass.V4_ROUTES.map(rng).sort((a, b) => a[0] - b[0]);
let cur = 0, ei = 0, ri = 0, cov = true;
const all = [...ex.map((r) => [...r, 'x']), ...rs.map((r) => [...r, 'r'])].sort((a, b) => a[0] - b[0]);
for (const [s, e] of all) { if (s !== cur) cov = false; cur = e + 1; }
ok(cov && cur === 2 ** 32, 'v4 complement tiles 0/0 exactly');
ok(LanBypass.V4_ROUTES.length === 72, 'v4 routes 72');
// §17.b④ fail-closed：ipv6 = false 也要 ::/0 + v6 排除段
ok(LanBypass.V6_FAIL_CLOSED === true && LanBypass.tunnelsV6(false) && LanBypass.tunnelsV6(true), 'v6 fail-closed');
const r4 = LanBypass.routes(false, '198.18.0.1', 'fdfe:dcba:9876::1');
ok(r4.length === 2 + 6 + 3, 'routes ipv6 off still: 2 defaults + 6 + 3 excluded ' + r4.length);
ok(r4.some((r) => r.destination.address.address === '::' && r.destination.prefixLength === 0 && r.isDefaultRoute && !r.isExcludedRoute), 'ipv6 off: ::/0 into tunnel');
ok(['fe80::', 'fc00::', 'ff00::'].every((a) => r4.some((r) => r.destination.address.address === a && r.isExcludedRoute)), 'ipv6 off: v6 LAN excluded');
ok(LanBypass.routes(false, 'a', 'b', true).length === 80, 'complement ipv6 off still 72+8');
ok(r4[0].isDefaultRoute && r4[0].destination.prefixLength === 0 && !r4[0].isExcludedRoute, 'default');
ok(r4.slice(2).every((r) => r.isExcludedRoute), 'rest excluded');
ok(JSON.stringify(r4) === JSON.stringify(LanBypass.routes(true, '198.18.0.1', 'fdfe:dcba:9876::1')), 'ipv6 on/off identical routes');
const r6 = LanBypass.routes(true, '198.18.0.1', 'fdfe:dcba:9876::1');
ok(r6.length === 2 + 6 + 3 && r6[1].destination.address.family === 2, 'routes v6');
ok(LanBypass.routes(true, 'a', 'b', true).length === 80, 'complement 72+8');
ok(TunBridges.clampMtu(100) === 1280 && TunBridges.clampMtu(99999) === 9000 && TunBridges.clampMtu(1500) === 1500 && TunBridges.clampMtu(NaN) === 1500, 'mtu clamp');
// StartIntent
const dir = fs.mkdtempSync(os.tmpdir() + '/si-');
const st = new StartIntentStore(dir);
ok(st.read() === undefined && st.generation() === 0, 'empty');
const a = st.write({ active: true, auto: false, mode: 'rule', mtu: 100, ipv6: true, excludedApps: ['com.x', 'com.app'], allowSimulated: true });
ok(a.generation === 1 && st.read().generation === 1 && st.read().active, 'write1');
const b = st.deactivate();
ok(b.generation === 2 && !st.read().active && st.read().mtu === 100, 'deactivate keeps params');
ok(fs.readdirSync(dir + '/vpn').length === 1, 'no tmp left: ' + fs.readdirSync(dir + '/vpn'));
ok(StartIntentStore.decode('{"v":2}') === undefined && StartIntentStore.decode('nope') === undefined && StartIntentStore.decode('null') === undefined, 'decode rejects');
const cfg = buildVpnConfig(a, 'com.app');
ok(cfg.mtu === 1280 && cfg.dnsAddresses[0] === '198.18.0.2' && cfg.addresses[0].address.address === '198.18.0.1' && cfg.addresses[0].prefixLength === 30, 'cfg addr/dns/mtu');
ok(JSON.stringify(cfg.blockedApplications) === '["com.app","com.x"]', 'blocked self first, dedup');
ok(cfg.addresses.length === 2 && cfg.isIPv6Accepted, 'v6 addr');
const cOff = buildVpnConfig({ ...a, ipv6: false }, 'com.app');
ok(cOff.addresses.length === 2 && cOff.addresses[1].address.address === 'fdfe:dcba:9876::1' && cOff.addresses[1].prefixLength === 126 && cOff.isIPv6Accepted, 'ipv6 off: still v6 addr + accepted');
ok(cOff.routes.some((r) => r.destination.address.address === '::' && r.destination.prefixLength === 0), 'ipv6 off cfg: ::/0');
// status
const ss = new VpnStatusStore(dir);
ss.write(2, VpnPhase.IDLE, false, undefined, undefined, 1234);
ss.write(3, VpnPhase.RUNNING, true);
const s = ss.read();
ok(s.generation === 3 && s.phase === 'running' && s.simulated && s.destroyedAt === 1234, 'status keeps destroyedAt');
// bridges
const sim = TunBridges.pick({ available: false }, dir, undefined);
ok(sim instanceof SimulatedTunBridge && !sim.createsTun, 'pick sim');
let started = null, stopped = 0;
const fake = { available: true, setMemoryLimit() {}, start: async (h, c, s) => { started = [h, c, s]; return undefined; }, stop() { stopped++; }, freeOSMemory() {} };
const nb = TunBridges.pick(fake, dir, async (fd, sock) => 'tun-fd: ' + fd);
ok(nb instanceof NativeTunBridge, 'pick native');
ok(await nb.start(7) === undefined && started[1] === 'tun-fd: 7' && started[2] === dir + '/ctl.sock', 'native start');
nb.stop(); nb.stop(); ok(stopped === 1, 'stop idempotent');
const nb2 = TunBridges.pick(fake, dir, async () => undefined);
ok(await nb2.start(7) === 'no active subscription', 'no sub');
console.log(bad ? `FAILED ${bad}` : 'vpn OK');
process.exit(bad ? 1 : 0);
