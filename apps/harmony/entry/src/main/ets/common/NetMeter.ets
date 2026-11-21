/*
 * 当前默认网络是否按流量计费（自动测速的“仅 Wi‑Fi 测速”，同 Android NetworkMonitor.state.metered / iOS isExpensive）。
 * 读不到（无网络、接口抛错）按不计费处理，与 Android AppGraph.network 为空时一致。需要 ohos.permission.GET_NETWORK_INFO（已声明）。
 */
import { connection } from '@kit.NetworkKit';

export class NetMeter {
  static isMetered(): boolean {
    try {
      const net = connection.getDefaultNetSync();
      if (net.netId === 0) {
        return false;
      }
      const caps = connection.getNetCapabilitiesSync(net);
      const list = caps.networkCap ?? [];
      return list.indexOf(connection.NetCap.NET_CAPABILITY_NOT_METERED) < 0;
    } catch (e) {
      return false;
    }
  }
}
