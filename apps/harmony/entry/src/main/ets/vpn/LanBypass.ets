/*
 * 契约 §16.a①（audit E10）：局域网、链路本地、回环、组播在任何模式（rule / global / direct）下都不进隧道，
 * 打印机、投屏、NAS、路由器管理页照常可用，也不会被发到远端节点。不可由用户开关。与 Android LanBypass、
 * iOS TunnelNetworkSettingsFactory.excludedRoutes 同一集合。
 *
 * 刻意 **不** 排除：198.18.0.0/16（fake-ip 与 tun 自己的 DNS 在这里）、100.64.0.0/10（运营商级 NAT，可能是公网服务）。
 *
 * 鸿蒙 API 20+ 的 RouteInfo 有 isExcludedRoute：默认路由 + 每个排除网段一条 isExcludedRoute = true（本工程 API 23）。
 * 万一真机上排除路由不生效（待验证），可改用 complement = true：直接下发 0/0 减去排除集的补集（V4_ROUTES / V6_ROUTES，
 * 与 Android API < 33 的表相同）。回环网段两种方式都不下发（内核 local 表本来就不走 tun）。
 */
import { vpnExtension } from '@kit.NetworkKit';

export const FAMILY_V4: number = 1;
export const FAMILY_V6: number = 2;
/** RouteInfo.interface 需要一个名字；VPN 框架以实际 tun 为准（参考实现均填此值）。 */
export const TUN_INTERFACE: string = 'vpn-tun';

export class LanBypass {
  static readonly V4_EXCLUDED: string[] = [
    '10.0.0.0/8', '127.0.0.0/8', '169.254.0.0/16', '172.16.0.0/12', '192.168.0.0/16', '224.0.0.0/4', '255.255.255.255/32'
  ];
  static readonly V6_EXCLUDED: string[] = ['fe80::/10', 'fc00::/7', 'ff00::/8'];

  /** 0.0.0.0/0 减去 V4_EXCLUDED 的最小 CIDR 覆盖（72 条），与 Android LanBypass.V4_ROUTES 一致。 */
  static readonly V4_ROUTES: string[] = [
    '0.0.0.0/5', '8.0.0.0/7', '11.0.0.0/8', '12.0.0.0/6', '16.0.0.0/4', '32.0.0.0/3', '64.0.0.0/3', '96.0.0.0/4',
    '112.0.0.0/5', '120.0.0.0/6', '124.0.0.0/7', '126.0.0.0/8', '128.0.0.0/3', '160.0.0.0/5', '168.0.0.0/8',
    '169.0.0.0/9', '169.128.0.0/10', '169.192.0.0/11', '169.224.0.0/12', '169.240.0.0/13', '169.248.0.0/14',
    '169.252.0.0/15', '169.255.0.0/16', '170.0.0.0/7', '172.0.0.0/12', '172.32.0.0/11', '172.64.0.0/10',
    '172.128.0.0/9', '173.0.0.0/8', '174.0.0.0/7', '176.0.0.0/4', '192.0.0.0/9', '192.128.0.0/11', '192.160.0.0/13',
    '192.169.0.0/16', '192.170.0.0/15', '192.172.0.0/14', '192.176.0.0/12', '192.192.0.0/10', '193.0.0.0/8',
    '194.0.0.0/7', '196.0.0.0/6', '200.0.0.0/5', '208.0.0.0/4', '240.0.0.0/5', '248.0.0.0/6', '252.0.0.0/7',
    '254.0.0.0/8', '255.0.0.0/9', '255.128.0.0/10', '255.192.0.0/11', '255.224.0.0/12', '255.240.0.0/13',
    '255.248.0.0/14', '255.252.0.0/15', '255.254.0.0/16', '255.255.0.0/17', '255.255.128.0/18', '255.255.192.0/19',
    '255.255.224.0/20', '255.255.240.0/21', '255.255.248.0/22', '255.255.252.0/23', '255.255.254.0/24',
    '255.255.255.0/25', '255.255.255.128/26', '255.255.255.192/27', '255.255.255.224/28', '255.255.255.240/29',
    '255.255.255.248/30', '255.255.255.252/31', '255.255.255.254/32'
  ];

  /** ::/0 减去 V6_EXCLUDED（8 条）。::1 在 ::/1 内但走 local 表，不会进 tun。 */
  static readonly V6_ROUTES: string[] = ['::/1', '8000::/2', 'c000::/3', 'e000::/4', 'f000::/5', 'f800::/6', 'fe00::/9', 'fec0::/10'];

  static isLoopback(cidr: string): boolean {
    return cidr.startsWith('127.') || cidr === '::1/128';
  }

  /** 'a.b.c.d/n' → LinkAddress。 */
  static link(cidr: string): vpnExtension.LinkAddress {
    const slash = cidr.indexOf('/');
    const addr = cidr.substring(0, slash);
    const len = Number.parseInt(cidr.substring(slash + 1), 10);
    const l: vpnExtension.LinkAddress = {
      address: { address: addr, family: addr.indexOf(':') >= 0 ? FAMILY_V6 : FAMILY_V4 },
      prefixLength: len
    };
    return l;
  }

  private static route(cidr: string, gateway: string, isDefault: boolean, excluded: boolean): vpnExtension.RouteInfo {
    const dest = LanBypass.link(cidr);
    const r: vpnExtension.RouteInfo = {
      interface: TUN_INTERFACE,
      destination: dest,
      gateway: { address: gateway, family: dest.address.family },
      hasGateway: false,
      isDefaultRoute: isDefault,
      isExcludedRoute: excluded
    };
    return r;
  }

  /**
   * 隧道路由：除 LAN 集合外的一切；IPv6 仅在 ipv6 开启时（§16.a④）。
   * gateway4 / gateway6：tun 自身地址（hasGateway = false，只为满足字段）。
   */
  static routes(ipv6: boolean, gateway4: string, gateway6: string, complement?: boolean): vpnExtension.RouteInfo[] {
    const out: vpnExtension.RouteInfo[] = [];
    if (complement === true) {
      for (const c of LanBypass.V4_ROUTES) {
        out.push(LanBypass.route(c, gateway4, false, false));
      }
      if (ipv6) {
        for (const c of LanBypass.V6_ROUTES) {
          out.push(LanBypass.route(c, gateway6, false, false));
        }
      }
      return out;
    }
    out.push(LanBypass.route('0.0.0.0/0', gateway4, true, false));
    if (ipv6) {
      out.push(LanBypass.route('::/0', gateway6, true, false));
    }
    for (const c of LanBypass.V4_EXCLUDED) {
      if (!LanBypass.isLoopback(c)) {
        out.push(LanBypass.route(c, gateway4, false, true));
      }
    }
    if (ipv6) {
      for (const c of LanBypass.V6_EXCLUDED) {
        out.push(LanBypass.route(c, gateway6, false, true));
      }
    }
    return out;
  }
}
