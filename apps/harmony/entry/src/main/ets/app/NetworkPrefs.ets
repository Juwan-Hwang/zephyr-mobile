/*
 * 受信任 Wi‑Fi 与本地代理端口的纯逻辑（M1-14；对照 Android di/SettingsStore TrustedWifi、core LocalProxyCredential、
 * ui/library LibraryPages）。页面只经这里算出下一份 Settings，再交 SettingsStore.update。
 */
import { copySettings, Settings } from '../engine/Model';
import { SettingsCodec } from '../engine/SettingsCodec';

export const PROXY_PORT_MIN: number = 1024;
export const PROXY_PORT_MAX: number = 65535;

export class TrustedWifi {
  static normalize(name: string): string {
    return name.trim();
  }

  /** §16.c：1–32 字节 UTF‑8、不重复、最多 50 个；不能加时返回 undefined。 */
  static add(s: Settings, name: string): Settings | undefined {
    const n = TrustedWifi.normalize(name);
    if (!SettingsCodec.validSsid(n) || s.trustedWifi.indexOf(n) >= 0 || s.trustedWifi.length >= SettingsCodec.TRUSTED_WIFI_MAX) {
      return undefined;
    }
    const next = copySettings(s);
    next.trustedWifi = s.trustedWifi.concat([n]);
    return next;
  }

  static remove(s: Settings, name: string): Settings {
    const next = copySettings(s);
    next.trustedWifi = s.trustedWifi.filter((w: string) => w !== name);
    return next;
  }
}

export class LocalProxy {
  static readonly USER: string = 'zephyr';

  /** 输入框只留数字、最多 5 位。 */
  static digits(input: string): string {
    return input.replace(new RegExp('[^0-9]', 'g'), '').substring(0, 5);
  }

  /** 合法端口（1024–65535）或 undefined。 */
  static parsePort(input: string): number | undefined {
    const t = input.trim();
    if (t.length === 0 || !new RegExp('^[0-9]+$').test(t)) {
      return undefined;
    }
    const p = Number(t);
    return p >= PROXY_PORT_MIN && p <= PROXY_PORT_MAX ? p : undefined;
  }

  static password(credential: string): string {
    const i = credential.indexOf(':');
    return i >= 0 ? credential.substring(i + 1) : credential;
  }

  /** 复制到剪贴板的地址：http://zephyr:<pw>@127.0.0.1:<port> / socks5://…。 */
  static url(scheme: string, credential: string, port: number): string {
    return `${scheme}://${credential}@127.0.0.1:${port}`;
  }

  /** 设置页一行的副标题：127.0.0.1:<port>（· 需要密码 由页面拼本地化文字）。 */
  static address(port: number): string {
    return `127.0.0.1:${port}`;
  }
}
