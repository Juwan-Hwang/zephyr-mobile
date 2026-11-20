/*
 * 引擎枚举 / 格式化结构 → 字符串、颜色资源（对照 Android ui/common/Labels.kt）。返回 Resource，由 Text 在绘制时解析，
 * 应用语言切换后自动跟随。$r 的键必须是字面量（编译期解析），所以这里全是 switch，不拼接键名。
 */
import { ConnectionStatus, ErrorCode, LogLevel, ProxyMode } from '../engine/Model';
import { AgoParts, AgoUnit, ExpiryKind, ExpiryParts, LatencyClass } from './Format';

export class Labels {
  static mode(m: ProxyMode): Resource {
    switch (m) {
      case ProxyMode.GLOBAL:
        return $r('app.string.common_mode_global');
      case ProxyMode.DIRECT:
        return $r('app.string.common_mode_direct');
      default:
        return $r('app.string.common_mode_rule');
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
        return $r('app.string.common_status_failed');
      default:
        return $r('app.string.common_status_disconnected');
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
  static importError(code: ErrorCode): Resource {
    switch (code) {
      case ErrorCode.SUBSCRIPTION_INVALID:
        return $r('app.string.subs_error_invalid_link');
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
        return $r('app.string.logs_level_debug');
      case LogLevel.WARNING:
        return $r('app.string.logs_level_warning');
      case LogLevel.ERROR:
        return $r('app.string.logs_level_error');
      default:
        return $r('app.string.logs_level_info');
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
}
