import { Accent, Appearance, defaultSettings, ProxyMode, Settings, TunStack } from './Model';
import { JsonKind, JsonReader, JsonValue } from './Json';

/*
 * 契约 §16.c（E42）设置逐字段宽松解码，对照 Android `SettingsCodec.kt`：缺字段、未知字段、单个字段类型 / 枚举 / 范围非法
 * 时只把该字段回落默认值，其余保持；嵌套对象（dns、tun）同样逐字段。绝不因一个字段失败重置整份设置。
 * 存储格式即 Settings 的 JSON（枚举存小写值，与 Model 枚举一致）。
 */

const PORT_MIN: number = 1024;
const PORT_MAX: number = 65535;
const MTU_MIN: number = 1280;
const MTU_MAX: number = 9000;

export class SettingsCodec {
  static readonly LATENCY_TTL_OPTIONS: number[] = [6, 12, 24, 72];
  static readonly AUTO_UPDATE_OPTIONS: number[] = [6, 12, 24, 48];
  static readonly TRUSTED_WIFI_MAX: number = 50;

  static encode(s: Settings): string {
    return JSON.stringify(s);
  }

  static decode(raw: string | undefined): Settings {
    const d = defaultSettings();
    const o = raw === undefined ? undefined : JsonReader.parse(raw);
    if (o === undefined || o.kind !== JsonKind.OBJECT) {
      return d;
    }
    d.onDemand = SettingsCodec.bool(o, 'onDemand', d.onDemand);
    d.trustedWifi = SettingsCodec.strings(o, 'trustedWifi', d.trustedWifi);
    d.disconnectOnTrusted = SettingsCodec.bool(o, 'disconnectOnTrusted', d.disconnectOnTrusted);
    d.localProxyEnabled = SettingsCodec.bool(o, 'localProxyEnabled', d.localProxyEnabled);
    d.localProxyPort = SettingsCodec.int(o, 'localProxyPort', d.localProxyPort);
    d.localProxyAuth = SettingsCodec.bool(o, 'localProxyAuth', d.localProxyAuth);
    d.testOnWifiOnly = SettingsCodec.bool(o, 'testOnWifiOnly', d.testOnWifiOnly);
    d.latencyTtlHours = SettingsCodec.int(o, 'latencyTtlHours', d.latencyTtlHours);
    d.autoUpdateHours = SettingsCodec.int(o, 'autoUpdateHours', d.autoUpdateHours);
    d.updateOnWifiOnly = SettingsCodec.bool(o, 'updateOnWifiOnly', d.updateOnWifiOnly);
    d.showChangesBeforeUpdate = SettingsCodec.bool(o, 'showChangesBeforeUpdate', d.showChangesBeforeUpdate);
    const dns = o.fields.get('dns');
    if (dns !== undefined && dns.kind === JsonKind.OBJECT) {
      d.dns.fakeIp = SettingsCodec.bool(dns, 'fakeIp', d.dns.fakeIp);
      d.dns.nameservers = SettingsCodec.strings(dns, 'nameservers', d.dns.nameservers);
      d.dns.fallback = SettingsCodec.strings(dns, 'fallback', d.dns.fallback);
      d.dns.ipv6 = SettingsCodec.bool(dns, 'ipv6', d.dns.ipv6);
    }
    const tun = o.fields.get('tun');
    if (tun !== undefined && tun.kind === JsonKind.OBJECT) {
      d.tun.stack = SettingsCodec.tunStack(SettingsCodec.str(tun, 'stack')) ?? d.tun.stack;
      d.tun.mtu = SettingsCodec.int(tun, 'mtu', d.tun.mtu);
      d.tun.ipv6 = SettingsCodec.bool(tun, 'ipv6', d.tun.ipv6);
      d.tun.strictRoute = SettingsCodec.bool(tun, 'strictRoute', d.tun.strictRoute);
    }
    d.accent = SettingsCodec.accent(SettingsCodec.str(o, 'accent')) ?? d.accent;
    d.appearance = SettingsCodec.appearance(SettingsCodec.str(o, 'appearance')) ?? d.appearance;
    d.shareDiagnostics = SettingsCodec.bool(o, 'shareDiagnostics', d.shareDiagnostics);
    return SettingsCodec.sanitized(d);
  }

  /** SSID：去首尾空白后 1–32 字节 UTF‑8。 */
  static validSsid(name: string): boolean {
    const n = utf8Length(name.trim());
    return n >= 1 && n <= 32;
  }

  static isValid(s: Settings): boolean {
    const seen = new Set<string>(s.trustedWifi);
    return s.localProxyPort >= PORT_MIN && s.localProxyPort <= PORT_MAX &&
      SettingsCodec.LATENCY_TTL_OPTIONS.indexOf(s.latencyTtlHours) >= 0 &&
      SettingsCodec.AUTO_UPDATE_OPTIONS.indexOf(s.autoUpdateHours) >= 0 &&
      s.tun.mtu >= MTU_MIN && s.tun.mtu <= MTU_MAX &&
      s.trustedWifi.length <= SettingsCodec.TRUSTED_WIFI_MAX && s.trustedWifi.every((w: string) => SettingsCodec.validSsid(w)) &&
      seen.size === s.trustedWifi.length;
  }

  /** 越界值只回落该字段默认值。 */
  static sanitized(s: Settings): Settings {
    const d = defaultSettings();
    if (!(s.localProxyPort >= PORT_MIN && s.localProxyPort <= PORT_MAX)) {
      s.localProxyPort = d.localProxyPort;
    }
    if (SettingsCodec.LATENCY_TTL_OPTIONS.indexOf(s.latencyTtlHours) < 0) {
      s.latencyTtlHours = d.latencyTtlHours;
    }
    if (SettingsCodec.AUTO_UPDATE_OPTIONS.indexOf(s.autoUpdateHours) < 0) {
      s.autoUpdateHours = d.autoUpdateHours;
    }
    if (!(s.tun.mtu >= MTU_MIN && s.tun.mtu <= MTU_MAX)) {
      s.tun.mtu = d.tun.mtu;
    }
    const wifi: string[] = [];
    for (const w of s.trustedWifi) {
      const t = w.trim();
      if (SettingsCodec.validSsid(t) && wifi.indexOf(t) < 0 && wifi.length < SettingsCodec.TRUSTED_WIFI_MAX) {
        wifi.push(t);
      }
    }
    s.trustedWifi = wifi;
    return s;
  }

  static proxyMode(v: string | undefined): ProxyMode | undefined {
    if (v === ProxyMode.RULE) {
      return ProxyMode.RULE;
    }
    if (v === ProxyMode.GLOBAL) {
      return ProxyMode.GLOBAL;
    }
    if (v === ProxyMode.DIRECT) {
      return ProxyMode.DIRECT;
    }
    return undefined;
  }

  private static accent(v: string | undefined): Accent | undefined {
    if (v === Accent.BLUE) {
      return Accent.BLUE;
    }
    if (v === Accent.GREEN) {
      return Accent.GREEN;
    }
    if (v === Accent.ORANGE) {
      return Accent.ORANGE;
    }
    if (v === Accent.PINK) {
      return Accent.PINK;
    }
    return undefined;
  }

  private static appearance(v: string | undefined): Appearance | undefined {
    if (v === Appearance.SYSTEM) {
      return Appearance.SYSTEM;
    }
    if (v === Appearance.DARK) {
      return Appearance.DARK;
    }
    if (v === Appearance.LIGHT) {
      return Appearance.LIGHT;
    }
    return undefined;
  }

  private static tunStack(v: string | undefined): TunStack | undefined {
    if (v === TunStack.SYSTEM) {
      return TunStack.SYSTEM;
    }
    if (v === TunStack.GVISOR) {
      return TunStack.GVISOR;
    }
    if (v === TunStack.MIXED) {
      return TunStack.MIXED;
    }
    return undefined;
  }

  private static bool(o: JsonValue, key: string, def: boolean): boolean {
    const v = o.fields.get(key);
    return v !== undefined && v.kind === JsonKind.BOOL ? v.text === 'true' : def;
  }

  /** 整数（kotlinx Int 语义：12.0、"12"、超 32 位都算非法）。 */
  private static int(o: JsonValue, key: string, def: number): number {
    const v = o.fields.get(key);
    if (v === undefined || v.kind !== JsonKind.NUMBER || !new RegExp('^-?(0|[1-9][0-9]*)$').test(v.text)) {
      return def;
    }
    const n = Number(v.text);
    return n >= -2147483648 && n <= 2147483647 ? n : def;
  }

  private static str(o: JsonValue, key: string): string | undefined {
    const v = o.fields.get(key);
    return v !== undefined && v.kind === JsonKind.STRING ? v.text : undefined;
  }

  /** 字符串数组；任一元素不是字符串则整个字段回落。 */
  private static strings(o: JsonValue, key: string, def: string[]): string[] {
    const v = o.fields.get(key);
    if (v === undefined || v.kind !== JsonKind.ARRAY || !v.items.every((x: JsonValue) => x.kind === JsonKind.STRING)) {
      return def;
    }
    return v.items.map((x: JsonValue) => x.text);
  }
}

function utf8Length(s: string): number {
  let n = 0;
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    if (c < 0x80) {
      n += 1;
    } else if (c < 0x800) {
      n += 2;
    } else if (c >= 0xD800 && c <= 0xDBFF && i + 1 < s.length) {
      n += 4;
      i++;
    } else {
      n += 3;
    }
  }
  return n;
}
