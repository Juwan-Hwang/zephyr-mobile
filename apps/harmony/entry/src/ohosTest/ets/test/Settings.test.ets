import { describe, expect, it } from '@ohos/hypium';
import { SettingsCodec } from '../../../main/ets/engine/SettingsCodec';
import { Accent, Appearance, copySettings, defaultSettings, ProxyMode, Settings, TunStack } from '../../../main/ets/engine/Model';
import { MockEngine } from '../../../main/ets/engine/MockEngine';
import { KEY_MODE, KEY_SETTINGS, KeyValueBackend, MemoryBackend, SettingsStore } from '../../../main/ets/app/SettingsStore';

/* 契约 §16.c（E42）逐字段宽松解码 + SettingsStore 落盘 / 回滚。 */

class FailingBackend implements KeyValueBackend {
  fail: boolean = false;
  readonly inner: MemoryBackend = new MemoryBackend();

  async get(key: string): Promise<string | undefined> {
    return this.inner.get(key);
  }

  async put(key: string, value: string): Promise<void> {
    if (this.fail) {
      throw new Error('disk full');
    }
    await this.inner.put(key, value);
  }
}

function json(s: Settings): string {
  return SettingsCodec.encode(s);
}

export default function settingsTest(): void {
  describe('SettingsCodec', () => {
    it('round trip', 0, () => {
      const s = defaultSettings();
      s.onDemand = false;
      s.trustedWifi = ['家', 'Office'];
      s.latencyTtlHours = 72;
      s.accent = Accent.PINK;
      s.appearance = Appearance.DARK;
      s.tun.stack = TunStack.MIXED;
      expect(json(SettingsCodec.decode(json(s)))).assertEqual(json(s));
    });

    it('garbage or empty → defaults', 0, () => {
      expect(json(SettingsCodec.decode('not json'))).assertEqual(json(defaultSettings()));
      expect(json(SettingsCodec.decode(undefined))).assertEqual(json(defaultSettings()));
      expect(json(SettingsCodec.decode('[1,2]'))).assertEqual(json(defaultSettings()));
    });

    it('v0.3-era settings: missing and unknown fields keep the rest', 0, () => {
      const old = '{"onDemand":false,"trustedWifi":["家"],"localProxyPort":7891,"shareAnonymousPattern":true,' +
        '"accent":"green","tun":{"mtu":1500}}';
      const s = SettingsCodec.decode(old);
      expect(s.onDemand).assertEqual(false);
      expect(JSON.stringify(s.trustedWifi)).assertEqual('["家"]');
      expect(s.localProxyPort).assertEqual(7891);
      expect(s.accent).assertEqual(Accent.GREEN);
      expect(s.tun.mtu).assertEqual(1500);
      expect(s.tun.stack).assertEqual(TunStack.GVISOR);
      expect(s.shareDiagnostics).assertEqual(false);
      expect(s.appearance).assertEqual(Appearance.SYSTEM);
    });

    it('one bad field falls back alone', 0, () => {
      const raw = '{"onDemand":"yes","testOnWifiOnly":false,"latencyTtlHours":5,"autoUpdateHours":48,' +
        '"localProxyPort":80,"accent":"purple","appearance":"light","tun":{"mtu":100,"ipv6":true},' +
        '"trustedWifi":["  a  ","a","","0123456789012345678901234567890123"]}';
      const s = SettingsCodec.decode(raw);
      expect(s.onDemand).assertEqual(true);
      expect(s.testOnWifiOnly).assertEqual(false);
      expect(s.latencyTtlHours).assertEqual(24);
      expect(s.autoUpdateHours).assertEqual(48);
      expect(s.localProxyPort).assertEqual(7890);
      expect(s.accent).assertEqual(Accent.BLUE);
      expect(s.appearance).assertEqual(Appearance.LIGHT);
      expect(s.tun.mtu).assertEqual(9000);
      expect(s.tun.ipv6).assertEqual(true);
      expect(JSON.stringify(s.trustedWifi)).assertEqual('["a"]');
      expect(SettingsCodec.isValid(s)).assertTrue();
    });

    it('non-integer numbers are invalid', 0, () => {
      const s = SettingsCodec.decode('{"latencyTtlHours":12.0,"autoUpdateHours":6}');
      expect(s.latencyTtlHours).assertEqual(24);
      expect(s.autoUpdateHours).assertEqual(6);
    });
  });

  describe('SettingsStore', () => {
    it('update persists, restore replays settings and mode', 0, async () => {
      const disk = new MemoryBackend();
      const a = new MockEngine({ latencyScale: 0 });
      const store = new SettingsStore(a, disk);
      await store.restore();
      const next = copySettings(a.settings().value);
      next.onDemand = false;
      next.appearance = Appearance.DARK;
      await store.update(next);
      await a.setMode(ProxyMode.GLOBAL);
      await Promise.resolve();
      expect(disk.values.get(KEY_MODE)).assertEqual('global');
      store.dispose();

      const b = new MockEngine({ latencyScale: 0 });
      const again = new SettingsStore(b, disk);
      await again.restore();
      expect(b.settings().value.onDemand).assertEqual(false);
      expect(b.settings().value.appearance).assertEqual(Appearance.DARK);
      expect(b.connectionState().value.mode).assertEqual(ProxyMode.GLOBAL);
      again.dispose();
    });

    it('write failure rolls back and rejects', 0, async () => {
      const disk = new FailingBackend();
      const e = new MockEngine({ latencyScale: 0 });
      const store = new SettingsStore(e, disk);
      await store.restore();
      const ok = copySettings(e.settings().value);
      ok.testOnWifiOnly = false;
      await store.update(ok);
      disk.fail = true;
      const bad = copySettings(e.settings().value);
      bad.shareDiagnostics = true;
      let threw = false;
      try {
        await store.update(bad);
      } catch (x) {
        threw = true;
      }
      expect(threw).assertTrue();
      expect(e.settings().value.shareDiagnostics).assertEqual(false);
      expect(e.settings().value.testOnWifiOnly).assertEqual(false);
      expect(SettingsCodec.decode(disk.inner.values.get(KEY_SETTINGS)).testOnWifiOnly).assertEqual(false);
      store.dispose();
    });
  });
}
