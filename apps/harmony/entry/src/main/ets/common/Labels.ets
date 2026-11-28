/*
 * 引擎枚举 / 格式化结构 → 字符串、颜色资源（对照 Android ui/common/Labels.kt）。返回 Resource，由 Text 在绘制时解析，
 * 应用语言切换后自动跟随。$r 的键必须是字面量（编译期解析），所以这里全是 switch，不拼接键名。
 */
import { ConnectionStatus, ErrorCode, LayerKind, LogLevel, ProxyMode, Scene, SceneKind } from '../engine/Model';
import { AgoParts, AgoUnit, ExpiryKind, ExpiryParts, LatencyClass } from './Format';
import { ZTerm } from '../generated/ZTerms';

export class Labels {
  static mode(m: ProxyMode): Resource {
    switch (m) {
      case ProxyMode.GLOBAL:
        return ZTerm.modeGlobal;
      case ProxyMode.DIRECT:
        return ZTerm.modeDirect;
      default:
        return ZTerm.modeRule;
    }
  }

  static modeHint(m: ProxyMode): Resource {
    switch (m) {
      case ProxyMode.GLOBAL:
        return $r('app.string.common_mode_global_hint');
      case ProxyMode.DIRECT:
        return $r('app.string.common_mode_direct_hint');
      default:
        return $r('app.string.common_mode_rule_hint');
    }
  }

  static status(s: ConnectionStatus): Resource {
    switch (s) {
      case ConnectionStatus.CONNECTED:
        return $r('app.string.common_status_connected');
      case ConnectionStatus.CONNECTING:
        return $r('app.string.common_status_connecting_ellipsis');
      case ConnectionStatus.DISCONNECTING:
        return $r('app.string.common_status_disconnecting');
      case ConnectionStatus.FAILED:
        return ZTerm.statusFailed;
      default:
        return ZTerm.statusDisconnected;
    }
  }

  /** 连接失败原因（首页）。未单独列出的码统一“出错了”，原始 message 只进日志（§0.5）。 */
  static connectError(code: ErrorCode): Resource {
    switch (code) {
      case ErrorCode.VPN_PERMISSION_DENIED:
        return $r('app.string.home_failure_vpn_permission');
      case ErrorCode.NETWORK_UNAVAILABLE:
        return $r('app.string.home_failure_network');
      case ErrorCode.SUBSCRIPTION_NOT_FOUND:
        return $r('app.string.home_failure_no_subscription');
      case ErrorCode.CORE_CRASHED:
        return $r('app.string.home_failure_core');
      default:
        return $r('app.string.hm_error_generic');
    }
  }

  /** 订阅导入 / 更新错误。 */
  /** fromFile：文件导入格式不对时说“不是有效的配置文件”（同 Android message(src = FILE)）。 */
  static importError(code: ErrorCode, fromFile: boolean = false): Resource {
    switch (code) {
      case ErrorCode.SUBSCRIPTION_INVALID:
        return fromFile ? $r('app.string.subs_error_invalid_file') : $r('app.string.subs_error_invalid_link');
      case ErrorCode.SUBSCRIPTION_FETCH_FAILED:
      case ErrorCode.NETWORK_UNAVAILABLE:
        return $r('app.string.subs_error_fetch');
      default:
        return $r('app.string.hm_error_generic');
    }
  }

  static logLevel(l: LogLevel): Resource {
    switch (l) {
      case LogLevel.DEBUG:
        return ZTerm.logDebug;
      case LogLevel.WARNING:
        return ZTerm.logWarning;
      case LogLevel.ERROR:
        return ZTerm.logError;
      default:
        return ZTerm.logInfo;
    }
  }

  static logLevelColor(l: LogLevel): Resource {
    switch (l) {
      case LogLevel.DEBUG:
        return $r('app.color.screen_t3');
      case LogLevel.WARNING:
        return $r('app.color.screen_amber');
      case LogLevel.ERROR:
        return $r('app.color.screen_red');
      default:
        return $r('app.color.screen_t2');
    }
  }

  static latencyColor(c: LatencyClass): Resource {
    switch (c) {
      case LatencyClass.NORMAL:
        return $r('app.color.latency_normal');
      case LatencyClass.SLOW:
        return $r('app.color.latency_slow');
      case LatencyClass.TIMEOUT:
        return $r('app.color.latency_timeout');
      default:
        return $r('app.color.latency_unknown');
    }
  }

  static ago(p: AgoParts): Resource {
    switch (p.unit) {
      case AgoUnit.MINUTES:
        return $r('app.string.hm_time_minutes_ago', p.count);
      case AgoUnit.HOURS:
        return $r('app.string.hm_time_hours_ago', p.count);
      case AgoUnit.DAYS:
        return $r('app.string.hm_time_days_ago', p.count);
      default:
        return $r('app.string.hm_time_just_now');
    }
  }

  static expiry(p: ExpiryParts): Resource {
    switch (p.kind) {
      case ExpiryKind.EXPIRED:
        return $r('app.string.hm_expiry_expired');
      case ExpiryKind.TODAY:
        return $r('app.string.hm_expiry_today');
      default:
        return $r('app.string.hm_expiry_in_days', p.days);
    }
  }

  /** 内置场景名随应用语言（核心用中文命名内置场景，Android Labels.builtInSceneNameRes）；自定义场景保留原名。 */
  static sceneName(s: Scene): ResourceStr {
    return s.kind !== SceneKind.CUSTOM ? Labels.sceneNameRaw(s.name) : s.name;
  }

  /** 只知道场景名（连接记录、故障切换）时：同 Android sceneNameText(raw)。 */
  static sceneNameRaw(raw: string): ResourceStr {
    if (raw === 'AI') {
      return $r('app.string.common_scene_ai');
    }
    if (raw === '视频') {
      return $r('app.string.common_scene_video');
    }
    if (raw === '其他') {
      return $r('app.string.common_scene_other');
    }
    return raw;
  }

  static layerKind(k: LayerKind): Resource {
    switch (k) {
      case LayerKind.OVERRIDE:
        return ZTerm.override;
      case LayerKind.SUBSCRIPTION:
        return ZTerm.subscription;
      case LayerKind.DOMAIN:
        return ZTerm.domain;
      case LayerKind.IP:
        return $r('app.string.rules_kind_ip');
      default:
        return $r('app.string.rules_kind_other');
    }
  }
}
