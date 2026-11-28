/*
 * VpnConfig 组装（纯函数，从 ZephyrVpnExtAbility 拆出，便于 node / ohosTest 对拍而不加载 ExtensionAbility）。
 */
import { vpnExtension } from '@kit.NetworkKit';
import { LanBypass } from './LanBypass';
import { StartIntent } from './StartIntent';
import { TunBridges } from './TunBridge';

/**
 * 纯函数，便于对拍：198.18.0.1/30、DNS 198.18.0.2、MTU 夹到 [1280, 9000]、自身 bundle 不走隧道。
 * IPv6 fail-closed（§17.b④）：v6 地址 fdfe:dcba:9876::1/126、::/0 路由、isIPv6Accepted 与 intent.ipv6 无关，始终配置；
 * intent.ipv6 只经运行时配置交给 mihomo（关闭时丢弃 v6）。
 */
export function buildVpnConfig(intent: StartIntent, selfBundle: string): vpnExtension.VpnConfig {
  const v6: boolean = LanBypass.tunnelsV6(intent.ipv6);
  const addresses: vpnExtension.LinkAddress[] = [LanBypass.link(TunBridges.TUN_ADDRESS4 + '/' + TunBridges.TUN_PREFIX4)];
  if (v6) {
    addresses.push(LanBypass.link(TunBridges.TUN_ADDRESS6 + '/' + TunBridges.TUN_PREFIX6));
  }
  const blocked: string[] = [selfBundle];
  for (const b of intent.excludedApps) {
    if (b.length > 0 && blocked.indexOf(b) < 0) {
      blocked.push(b);
    }
  }
  const cfg: vpnExtension.VpnConfig = {
    addresses: addresses,
    routes: LanBypass.routes(intent.ipv6, TunBridges.TUN_ADDRESS4, TunBridges.TUN_ADDRESS6),
    dnsAddresses: [TunBridges.TUN_DNS],
    mtu: TunBridges.clampMtu(intent.mtu),
    isIPv4Accepted: true,
    isIPv6Accepted: v6,
    isBlocking: false,
    // UI 进程与自身其他出站保持直连（避免回环）；用户排除的应用同理。
    blockedApplications: blocked
  };
  return cfg;
}
