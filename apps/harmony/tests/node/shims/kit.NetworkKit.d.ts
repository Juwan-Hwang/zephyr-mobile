import { Want, common } from './kit.AbilityKit';
export namespace connection {
  interface NetAddress { address: string; family?: number; port?: number }
  interface LinkAddress { address: NetAddress; prefixLength: number }
  interface RouteInfo { interface: string; destination: LinkAddress; gateway: NetAddress; hasGateway: boolean; isDefaultRoute: boolean; isExcludedRoute?: boolean }
}
export class VpnExtensionContext { filesDir: string; applicationInfo: common.ApplicationInfo }
export class VpnExtensionAbility {
  context: VpnExtensionContext;
  onCreate(want: Want): void;
  onDestroy(): void;
}
export namespace vpnExtension {
  type LinkAddress = connection.LinkAddress;
  type RouteInfo = connection.RouteInfo;
  function startVpnExtensionAbility(want: Want): Promise<void>;
  function stopVpnExtensionAbility(want: Want): Promise<void>;
  function createVpnConnection(context: VpnExtensionContext): VpnConnection;
  interface VpnConnection {
    create(config: VpnConfig): Promise<number>;
    protect(socketFd: number): Promise<void>;
    destroy(): Promise<void>;
    protectProcessNet(): Promise<void>;
  }
  interface VpnConfig {
    vpnId?: string; addresses: Array<LinkAddress>; routes?: Array<RouteInfo>; dnsAddresses?: Array<string>;
    searchDomains?: Array<string>; mtu?: number; isIPv4Accepted?: boolean; isIPv6Accepted?: boolean;
    isInternal?: boolean; isBlocking?: boolean; trustedApplications?: Array<string>; blockedApplications?: Array<string>;
  }
}
