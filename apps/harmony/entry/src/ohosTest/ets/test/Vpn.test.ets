import { describe, expect, it } from '@ohos/hypium';
import { vpnExtension } from '@kit.NetworkKit';
import { LanBypass } from '../../../main/ets/vpn/LanBypass';
import { StartIntent, START_INTENT_VERSION } from '../../../main/ets/vpn/StartIntent';
import { buildVpnConfig } from '../../../main/ets/vpn/VpnConfigBuilder';

/* 契约 §17.b④：IPv6 真机确认前 fail-closed —— 无论 ipv6 开关，tun 都配 v6 地址、::/0 进隧道、接收 v6。 */

function intent(ipv6: boolean): StartIntent {
  const i: StartIntent = {
    v: START_INTENT_VERSION, generation: 1, active: true, at: 0, auto: false, mode: 'rule', mtu: 1500,
    ipv6: ipv6, excludedApps: [], allowSimulated: true
  };
  return i;
}

function hasV6Default(routes: vpnExtension.RouteInfo[]): boolean {
  return routes.some((r: vpnExtension.RouteInfo) => r.destination.address.address === '::' &&
    r.destination.prefixLength === 0 && r.isExcludedRoute !== true);
}

function excluded(routes: vpnExtension.RouteInfo[], addr: string): boolean {
  return routes.some((r: vpnExtension.RouteInfo) => r.destination.address.address === addr && r.isExcludedRoute === true);
}

export default function vpnTest(): void {
  describe('VpnIpv6FailClosed', () => {
    it('routes ::/0 into the tunnel even with ipv6 off', 0, () => {
      expect(LanBypass.V6_FAIL_CLOSED).assertTrue();
      expect(LanBypass.tunnelsV6(false)).assertTrue();
      const off = LanBypass.routes(false, '198.18.0.1', 'fdfe:dcba:9876::1');
      expect(hasV6Default(off)).assertTrue();
      expect(excluded(off, 'fe80::') && excluded(off, 'fc00::') && excluded(off, 'ff00::')).assertTrue();
      expect(excluded(off, '127.0.0.0')).assertFalse();
      expect(JSON.stringify(off)).assertEqual(JSON.stringify(LanBypass.routes(true, '198.18.0.1', 'fdfe:dcba:9876::1')));
      expect(LanBypass.routes(false, 'a', 'b', true).length).assertEqual(LanBypass.V4_ROUTES.length + LanBypass.V6_ROUTES.length);
    });

    it('vpn config always has a v6 address and accepts v6', 0, () => {
      for (const v6 of [false, true]) {
        const cfg = buildVpnConfig(intent(v6), 'com.juwanh.zephyr');
        expect(cfg.addresses.length).assertEqual(2);
        expect(cfg.addresses[1].address.address).assertEqual('fdfe:dcba:9876::1');
        expect(cfg.addresses[1].prefixLength).assertEqual(126);
        expect(cfg.isIPv6Accepted).assertTrue();
        expect(hasV6Default(cfg.routes ?? [])).assertTrue();
      }
    });
  });
}
