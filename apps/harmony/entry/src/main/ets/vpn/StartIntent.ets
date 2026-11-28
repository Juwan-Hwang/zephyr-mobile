/*
 * UI 进程 ↔ VPN 扩展进程（:vpn）之间的两份小文件，都在 filesDir/vpn/ 下，一律“写临时文件 + fsync + rename”原子替换：
 * - start-intent.json：UI 写、扩展读。扩展 onCreate 时按它决定连不连；generation 每次写入 +1，
 *   扩展在每个 await 之后对比当前文件里的 generation，被更新的（用户又点了断开 / 重连）就放弃本轮。
 * - status.json：扩展写、UI 读（VpnController 轮询）。只认 generation 与当前意图一致的状态，旧实例的迟到写入被忽略。
 * VpnExtensionAbility 的 onCreate(want) 拿不到 UI 传的参数（startVpnExtensionAbility 的 Want 只用于定位扩展），
 * 也可能被系统直接拉起（始终开启 / 进程重启），所以意图必须落盘，不能放内存。
 */
import { fileIo } from '@kit.CoreFileKit';

export const VPN_DIR: string = 'vpn';
/** module.json5 里 extensionAbilities 的 name。 */
export const VPN_ABILITY_NAME: string = 'ZephyrVpnExtAbility';
/** 上一个扩展实例销毁后，至少等这么久再 create（VPN 框架 destroy 是异步的）。 */
export const RECREATE_DELAY_MS: number = 500;
const INTENT_FILE: string = 'start-intent.json';
const STATUS_FILE: string = 'status.json';

/** 原子写：同目录临时文件 → fsync → rename（同一文件系统内 rename 是原子的，读方要么看到旧内容要么看到新内容）。 */
export function writeFileAtomic(dir: string, name: string, text: string): void {
  if (!fileIo.accessSync(dir)) {
    fileIo.mkdirSync(dir, true);
  }
  const target = dir + '/' + name;
  const tmp = target + '.tmp-' + Date.now().toString(36) + '-' + Math.floor(Math.random() * 1e9).toString(36);
  const f = fileIo.openSync(tmp, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
  try {
    fileIo.writeSync(f.fd, text);
    fileIo.fsyncSync(f.fd);
  } finally {
    fileIo.closeSync(f);
  }
  try {
    fileIo.renameSync(tmp, target);
  } catch (e) {
    try {
      fileIo.unlinkSync(tmp);
    } catch (ignored) {
      // 临时文件残留无害，下次写入换新名字。
    }
    throw e as Error;
  }
}

/** 不存在 / 读失败 → undefined（调用方按“无意图”处理）。 */
export function readFileText(dir: string, name: string): string | undefined {
  const path = dir + '/' + name;
  try {
    if (!fileIo.accessSync(path)) {
      return undefined;
    }
    return fileIo.readTextSync(path);
  } catch (e) {
    return undefined;
  }
}

// ── 启动意图 ─────────────────────────────────────────────────────────────

/** 落盘格式（v1）。字段名即 JSON 键。 */
export interface StartIntent {
  v: number;
  /** 单调递增；每次 write（连 / 断）都 +1。 */
  generation: number;
  /** true = 应该连着；false = 用户断开（扩展被系统拉起时据此自行退出）。 */
  active: boolean;
  /** 写入时间（ms）。 */
  at: number;
  /** true = 按需连接 / 系统重启拉起；false = 用户手动（§16.a⑤）。 */
  auto: boolean;
  /** ProxyMode 序列化名（rule / global / direct）。 */
  mode: string;
  mtu: number;
  ipv6: boolean;
  /** 额外不走隧道的应用（bundleName）；自身 bundle 由扩展另加，不在这里。 */
  excludedApps: string[];
  /** 没有原生内核时允许“模拟连接”（Mock 引擎 / 调试）。Release + 真实引擎一律 false：没有隧道就不能说已连接。 */
  allowSimulated: boolean;
}

/** write() 的输入：generation / at / v 由存储层填。 */
export interface StartIntentInput {
  active: boolean;
  auto: boolean;
  mode: string;
  mtu: number;
  ipv6: boolean;
  excludedApps: string[];
  allowSimulated: boolean;
}

export const START_INTENT_VERSION: number = 1;

function isStringArray(v: Object | undefined | null): boolean {
  if (!Array.isArray(v)) {
    return false;
  }
  const a = v as Object[];
  for (const x of a) {
    if (typeof x !== 'string') {
      return false;
    }
  }
  return true;
}

export class StartIntentStore {
  private dir: string;

  /** filesDir：UIAbilityContext / VpnExtensionContext 的 filesDir（同一应用沙箱，两进程共享）。 */
  constructor(filesDir: string) {
    this.dir = filesDir + '/' + VPN_DIR;
  }

  /** 解析失败、版本不认识、字段缺失 → undefined。 */
  read(): StartIntent | undefined {
    const text = readFileText(this.dir, INTENT_FILE);
    if (text === undefined) {
      return undefined;
    }
    return StartIntentStore.decode(text);
  }

  static decode(text: string): StartIntent | undefined {
    let o: StartIntent;
    try {
      o = JSON.parse(text) as StartIntent;
    } catch (e) {
      return undefined;
    }
    if (o === null || typeof o !== 'object' || o.v !== START_INTENT_VERSION) {
      return undefined;
    }
    if (typeof o.generation !== 'number' || typeof o.active !== 'boolean' || typeof o.at !== 'number' ||
      typeof o.auto !== 'boolean' || typeof o.mode !== 'string' || typeof o.mtu !== 'number' ||
      typeof o.ipv6 !== 'boolean' || !isStringArray(o.excludedApps) || typeof o.allowSimulated !== 'boolean') {
      return undefined;
    }
    const r: StartIntent = {
      v: o.v,
      generation: o.generation,
      active: o.active,
      at: o.at,
      auto: o.auto,
      mode: o.mode,
      mtu: o.mtu,
      ipv6: o.ipv6,
      excludedApps: o.excludedApps.slice(),
      allowSimulated: o.allowSimulated
    };
    return r;
  }

  static encode(i: StartIntent): string {
    return JSON.stringify(i);
  }

  /** 当前 generation（无文件 = 0）。 */
  generation(): number {
    const cur = this.read();
    return cur === undefined ? 0 : cur.generation;
  }

  /** generation = 旧值 + 1，原子落盘，返回写入的意图。只在 UI 进程调用（单写者）。 */
  write(input: StartIntentInput): StartIntent {
    const next: StartIntent = {
      v: START_INTENT_VERSION,
      generation: this.generation() + 1,
      active: input.active,
      at: Date.now(),
      auto: input.auto,
      mode: input.mode,
      mtu: input.mtu,
      ipv6: input.ipv6,
      excludedApps: input.excludedApps.slice(),
      allowSimulated: input.allowSimulated
    };
    writeFileAtomic(this.dir, INTENT_FILE, StartIntentStore.encode(next));
    return next;
  }

  /** 断开：沿用上次参数，只把 active 置 false（generation 仍 +1，让进行中的启动作废）。 */
  deactivate(): StartIntent {
    const cur = this.read();
    const input: StartIntentInput = {
      active: false,
      auto: false,
      mode: cur === undefined ? 'rule' : cur.mode,
      mtu: cur === undefined ? 1500 : cur.mtu,
      ipv6: cur === undefined ? false : cur.ipv6,
      excludedApps: cur === undefined ? [] : cur.excludedApps,
      allowSimulated: cur === undefined ? false : cur.allowSimulated
    };
    return this.write(input);
  }
}

// ── 扩展回报的状态 ───────────────────────────────────────────────────────

export enum VpnPhase {
  IDLE = 'idle',
  STARTING = 'starting',
  RUNNING = 'running',
  STOPPING = 'stopping',
  FAILED = 'failed'
}

export interface VpnStatus {
  v: number;
  /** 对应的启动意图 generation。 */
  generation: number;
  phase: VpnPhase;
  /** true = 没建 tun 的模拟连接（SimulatedTunBridge）。 */
  simulated: boolean;
  at: number;
  /** ErrorCode 序列化名（phase = failed 时）。 */
  errorCode?: string;
  /** 只进日志（§0.5）。 */
  errorMessage?: string;
  /** 上一个扩展实例 onDestroy 的时间（ms）；新实例据此等够 ~500 ms 再 create（见 ZephyrVpnExtAbility）。 */
  destroyedAt?: number;
}

export class VpnStatusStore {
  private dir: string;

  constructor(filesDir: string) {
    this.dir = filesDir + '/' + VPN_DIR;
  }

  read(): VpnStatus | undefined {
    const text = readFileText(this.dir, STATUS_FILE);
    if (text === undefined) {
      return undefined;
    }
    let o: VpnStatus;
    try {
      o = JSON.parse(text) as VpnStatus;
    } catch (e) {
      return undefined;
    }
    if (o === null || typeof o !== 'object' || o.v !== 1 || typeof o.generation !== 'number' ||
      typeof o.phase !== 'string' || typeof o.simulated !== 'boolean' || typeof o.at !== 'number') {
      return undefined;
    }
    const s: VpnStatus = {
      v: 1,
      generation: o.generation,
      phase: VpnStatusStore.phaseOf(o.phase),
      simulated: o.simulated,
      at: o.at,
      errorCode: typeof o.errorCode === 'string' ? o.errorCode : undefined,
      errorMessage: typeof o.errorMessage === 'string' ? o.errorMessage : undefined,
      destroyedAt: typeof o.destroyedAt === 'number' ? o.destroyedAt : undefined
    };
    return s;
  }

  private static phaseOf(p: string): VpnPhase {
    switch (p) {
      case 'starting':
        return VpnPhase.STARTING;
      case 'running':
        return VpnPhase.RUNNING;
      case 'stopping':
        return VpnPhase.STOPPING;
      case 'failed':
        return VpnPhase.FAILED;
      default:
        return VpnPhase.IDLE;
    }
  }

  /** 只在扩展进程调用（单写者）。destroyedAt 未给时沿用文件里已有的值。 */
  write(generation: number, phase: VpnPhase, simulated: boolean, errorCode?: string, errorMessage?: string,
    destroyedAt?: number): VpnStatus {
    let keepDestroyed = destroyedAt;
    if (keepDestroyed === undefined) {
      const prev = this.read();
      keepDestroyed = prev === undefined ? undefined : prev.destroyedAt;
    }
    const s: VpnStatus = {
      v: 1,
      generation: generation,
      phase: phase,
      simulated: simulated,
      at: Date.now(),
      errorCode: errorCode,
      errorMessage: errorMessage,
      destroyedAt: keepDestroyed
    };
    writeFileAtomic(this.dir, STATUS_FILE, JSON.stringify(s));
    return s;
  }
}
