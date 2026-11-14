//! mihomo REST 客户端（external-controller-unix）。两端共用一份实现：策略组、延迟测试、活动连接、连接轨迹。
//!
//! 只用 std 的 UnixStream + 手写 HTTP/1.1（Connection: close，支持 Content-Length 与 chunked），
//! 不引入 hyper/tokio，扩展进程内存与体积都更小。调用是阻塞的：平台在后台线程/协程里调用。

use crate::error::MobileError;
use serde_json::Value;
use std::collections::HashMap;
use std::io::{Read, Write};
use std::time::Duration;

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum GroupType {
    Select,
    UrlTest,
    Fallback,
    LoadBalance,
    Relay,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct PolicyGroup {
    pub name: String,
    pub group_type: GroupType,
    pub selected: Option<String>,
    pub member_count: i32,
    /// 组内最近一次测速时间（毫秒），来自成员 history
    pub tested_at: Option<i64>,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct GroupMember {
    pub name: String,
    pub proxy_type: String,
    /// 最近一次延迟；-1 = 超时；None = 未测
    pub latency_ms: Option<i32>,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct ConnectionInfo {
    pub id: String,
    pub host: String,
    /// iOS 恒为 None
    pub app: Option<String>,
    /// 命中的顶层策略组（场景）
    pub scene: Option<String>,
    /// 实际出口节点；直连 = "DIRECT"
    pub node: String,
    pub up_bytes: i64,
    pub down_bytes: i64,
    pub started_at: i64,
    pub rule: String,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct HostActivity {
    pub host: String,
    pub scene: Option<String>,
    pub node: String,
    pub connections: i32,
    pub total_bytes: i64,
    pub last_seen_at: i64,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct HostTrace {
    pub host: String,
    pub last_seen_at: i64,
    pub connections: i32,
    pub total_bytes: i64,
    /// "DOMAIN-SUFFIX,claude.ai"
    pub rule: String,
    /// 策略链，自顶层组到出口节点（["AI", "US Fixed IP", "US-Fixed-01"]）
    pub chain: Vec<String>,
    pub scene: Option<String>,
    pub node: String,
}

pub struct Http {
    sock: String,
    timeout: Duration,
}

impl Http {
    pub fn new(sock: &str) -> Self {
        Self { sock: sock.into(), timeout: Duration::from_secs(10) }
    }

    pub fn request(&self, method: &str, path: &str, body: Option<&str>) -> Result<(u16, String), MobileError> {
        #[cfg(unix)]
        {
            let mut s = std::os::unix::net::UnixStream::connect(&self.sock).map_err(|e| MobileError::NotRunning(format!("{}: {e}", self.sock)))?;
            s.set_read_timeout(Some(self.timeout))?;
            s.set_write_timeout(Some(self.timeout))?;
            let b = body.unwrap_or("");
            let req = format!(
                "{method} {path} HTTP/1.1\r\nHost: mihomo\r\nConnection: close\r\nAccept: application/json\r\n{}Content-Length: {}\r\n\r\n{b}",
                if body.is_some() { "Content-Type: application/json\r\n" } else { "" },
                b.len()
            );
            s.write_all(req.as_bytes())?;
            let mut raw = Vec::new();
            s.read_to_end(&mut raw)?;
            parse_response(&raw)
        }
        #[cfg(not(unix))]
        {
            let _ = (method, path, body);
            Err(MobileError::NotRunning("unix socket unsupported".into()))
        }
    }

    pub fn json(&self, method: &str, path: &str, body: Option<&str>) -> Result<Value, MobileError> {
        let (code, text) = self.request(method, path, body)?;
        if !(200..300).contains(&code) {
            let msg = serde_json::from_str::<Value>(&text).ok().and_then(|v| v.get("message").and_then(|m| m.as_str()).map(String::from)).unwrap_or(text);
            return Err(match code {
                404 => MobileError::NotFound(msg),
                400 => MobileError::Invalid(msg),
                _ => MobileError::Io(format!("mihomo {code}: {msg}")),
            });
        }
        if text.trim().is_empty() {
            return Ok(Value::Null);
        }
        serde_json::from_str(&text).map_err(|e| MobileError::Io(format!("mihomo json: {e}")))
    }
}

pub fn parse_response(raw: &[u8]) -> Result<(u16, String), MobileError> {
    let split = raw.windows(4).position(|w| w == b"\r\n\r\n").ok_or_else(|| MobileError::Io("http: 响应不完整".into()))?;
    let head = String::from_utf8_lossy(&raw[..split]);
    let mut lines = head.split("\r\n");
    let status: u16 = lines.next().and_then(|l| l.split_whitespace().nth(1)).and_then(|c| c.parse().ok()).ok_or_else(|| MobileError::Io("http: 状态行".into()))?;
    let headers: HashMap<String, String> = lines.filter_map(|l| l.split_once(':')).map(|(k, v)| (k.trim().to_ascii_lowercase(), v.trim().to_string())).collect();
    let body = &raw[split + 4..];
    let body = if headers.get("transfer-encoding").is_some_and(|v| v.eq_ignore_ascii_case("chunked")) {
        let mut out = Vec::new();
        let mut p = 0;
        loop {
            let le = body[p..].windows(2).position(|w| w == b"\r\n").ok_or_else(|| MobileError::Io("http: chunk".into()))?;
            let size_s = String::from_utf8_lossy(&body[p..p + le]);
            let size = usize::from_str_radix(size_s.split(';').next().unwrap_or("").trim(), 16).map_err(|_| MobileError::Io("http: chunk size".into()))?;
            p += le + 2;
            if size == 0 {
                break;
            }
            if p + size > body.len() {
                return Err(MobileError::Io("http: chunk 截断".into()));
            }
            out.extend_from_slice(&body[p..p + size]);
            p += size + 2;
        }
        out
    } else if let Some(n) = headers.get("content-length").and_then(|v| v.parse::<usize>().ok()) {
        body[..n.min(body.len())].to_vec()
    } else {
        body.to_vec()
    };
    Ok((status, String::from_utf8_lossy(&body).into_owned()))
}

/// RFC 3339 → 毫秒（mihomo 的 start 字段，如 2026-11-06T13:00:00.123456789+08:00 / ...Z）。
pub fn rfc3339_millis(s: &str) -> Option<i64> {
    let b = s.as_bytes();
    if b.len() < 20 {
        return None;
    }
    let n = |a: usize, l: usize| s.get(a..a + l)?.parse::<i64>().ok();
    let (y, mo, d, h, mi, se) = (n(0, 4)?, n(5, 2)?, n(8, 2)?, n(11, 2)?, n(14, 2)?, n(17, 2)?);
    let mut p = 19;
    let mut ms = 0i64;
    if b.get(p) == Some(&b'.') {
        p += 1;
        let st = p;
        while p < b.len() && b[p].is_ascii_digit() {
            p += 1;
        }
        let frac = &s[st..p];
        let f3: String = frac.chars().chain("000".chars()).take(3).collect();
        ms = f3.parse().ok()?;
    }
    let off = match b.get(p)? {
        b'Z' | b'z' => 0,
        sign @ (b'+' | b'-') => {
            let oh = n(p + 1, 2)?;
            let om = n(p + 4, 2)?;
            let v = (oh * 60 + om) * 60;
            if *sign == b'+' {
                v
            } else {
                -v
            }
        }
        _ => return None,
    };
    // days from civil（Howard Hinnant）
    let (y2, m2) = if mo <= 2 { (y - 1, mo + 9) } else { (y, mo - 3) };
    let era = y2.div_euclid(400);
    let yoe = y2 - era * 400;
    let doy = (153 * m2 + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    let days = era * 146_097 + doe - 719_468;
    Some(((days * 86_400 + h * 3600 + mi * 60 + se) - off) * 1000 + ms)
}

fn enc(s: &str) -> String {
    let mut o = String::new();
    for &c in s.as_bytes() {
        if c.is_ascii_alphanumeric() || b"-._~".contains(&c) {
            o.push(c as char);
        } else {
            o += &format!("%{c:02X}");
        }
    }
    o
}

fn group_type(t: &str) -> Option<GroupType> {
    Some(match t {
        "Selector" => GroupType::Select,
        "URLTest" => GroupType::UrlTest,
        "Fallback" => GroupType::Fallback,
        "LoadBalance" => GroupType::LoadBalance,
        "Relay" => GroupType::Relay,
        _ => return None,
    })
}

fn last_delay(p: &Value) -> Option<(i32, i64)> {
    let h = p.get("history")?.as_array()?.last()?;
    let d = h.get("delay")?.as_i64()? as i32;
    let at = h.get("time").and_then(|t| t.as_str()).and_then(rfc3339_millis).unwrap_or(0);
    Some((if d == 0 { -1 } else { d }, at))
}

fn conn_from(v: &Value) -> Option<ConnectionInfo> {
    let m = v.get("metadata")?;
    let host = m.get("host").and_then(|x| x.as_str()).filter(|x| !x.is_empty()).or_else(|| m.get("destinationIP").and_then(|x| x.as_str()))?.to_string();
    let chains: Vec<String> = v.get("chains").and_then(|c| c.as_array()).map(|a| a.iter().filter_map(|x| x.as_str().map(String::from)).collect()).unwrap_or_default();
    let rule = v.get("rule").and_then(|x| x.as_str()).unwrap_or("");
    let payload = v.get("rulePayload").and_then(|x| x.as_str()).unwrap_or("");
    Some(ConnectionInfo {
        id: v.get("id")?.as_str()?.to_string(),
        host,
        app: m.get("process").and_then(|x| x.as_str()).filter(|x| !x.is_empty()).map(String::from),
        // chains：[出口节点, …, 顶层组]
        scene: if chains.len() > 1 { chains.last().cloned() } else { None },
        node: chains.first().cloned().unwrap_or_else(|| "DIRECT".into()),
        up_bytes: v.get("upload").and_then(|x| x.as_i64()).unwrap_or(0),
        down_bytes: v.get("download").and_then(|x| x.as_i64()).unwrap_or(0),
        started_at: v.get("start").and_then(|x| x.as_str()).and_then(rfc3339_millis).unwrap_or(0),
        rule: if payload.is_empty() { rule.to_string() } else { format!("{rule},{payload}") },
    })
}

#[derive(uniffi::Object)]
pub struct MihomoClient {
    http: Http,
}

#[uniffi::export]
impl MihomoClient {
    /// socket：zm_start 时传入的 external-controller-unix 路径。
    #[uniffi::constructor]
    pub fn new(socket_path: String) -> std::sync::Arc<Self> {
        std::sync::Arc::new(Self { http: Http::new(&socket_path) })
    }

    pub fn version(&self) -> Result<String, MobileError> {
        Ok(self.http.json("GET", "/version", None)?.get("version").and_then(|v| v.as_str()).unwrap_or("").to_string())
    }

    /// 策略组，按配置文件顺序（GLOBAL 组里的顺序；没有则按名称）。
    pub fn policy_groups(&self) -> Result<Vec<PolicyGroup>, MobileError> {
        let v = self.http.json("GET", "/proxies", None)?;
        let proxies = v.get("proxies").and_then(|p| p.as_object()).ok_or_else(|| MobileError::Io("mihomo: proxies".into()))?;
        let order: Vec<String> = proxies.get("GLOBAL").and_then(|g| g.get("all")).and_then(|a| a.as_array()).map(|a| a.iter().filter_map(|x| x.as_str().map(String::from)).collect()).unwrap_or_default();
        let mut names: Vec<&String> = proxies.keys().filter(|k| k.as_str() != "GLOBAL").collect();
        names.sort_by_key(|n| (order.iter().position(|o| o == *n).unwrap_or(usize::MAX), (*n).clone()));
        Ok(names
            .into_iter()
            .filter_map(|n| {
                let p = &proxies[n];
                let gt = group_type(p.get("type")?.as_str()?)?;
                let all = p.get("all").and_then(|a| a.as_array());
                let tested = all.and_then(|a| a.iter().filter_map(|m| m.as_str().and_then(|m| proxies.get(m)).and_then(last_delay)).map(|x| x.1).max());
                Some(PolicyGroup {
                    name: n.clone(),
                    group_type: gt,
                    selected: p.get("now").and_then(|x| x.as_str()).map(String::from),
                    member_count: all.map(|a| a.len() as i32).unwrap_or(0),
                    tested_at: tested.filter(|&t| t > 0),
                })
            })
            .collect())
    }

    /// 组成员分页（contract §4 limit ≤ 500）。
    pub fn group_members(&self, group: String, offset: u32, limit: u32) -> Result<Vec<GroupMember>, MobileError> {
        let v = self.http.json("GET", "/proxies", None)?;
        let proxies = v.get("proxies").and_then(|p| p.as_object()).ok_or_else(|| MobileError::Io("mihomo: proxies".into()))?;
        let g = proxies.get(&group).ok_or_else(|| MobileError::NotFound(format!("group {group}")))?;
        let all = g.get("all").and_then(|a| a.as_array()).cloned().unwrap_or_default();
        Ok(all
            .iter()
            .skip(offset as usize)
            .take(limit.min(500) as usize)
            .filter_map(|m| m.as_str())
            .map(|m| {
                let p = proxies.get(m);
                GroupMember {
                    name: m.to_string(),
                    proxy_type: p.and_then(|p| p.get("type")).and_then(|t| t.as_str()).unwrap_or("").to_string(),
                    latency_ms: p.and_then(last_delay).map(|x| x.0),
                }
            })
            .collect())
    }

    pub fn select_in_group(&self, group: String, member: String) -> Result<(), MobileError> {
        let body = serde_json::json!({ "name": member }).to_string();
        self.http.json("PUT", &format!("/proxies/{}", enc(&group)), Some(&body)).map(|_| ())
    }

    /// 只测该组；返回 (成员, 毫秒)，超时 = -1。
    pub fn test_group(&self, group: String, url: String, timeout_ms: u32) -> Result<Vec<GroupMember>, MobileError> {
        let v = self.http.json("GET", &format!("/group/{}/delay?url={}&timeout={timeout_ms}", enc(&group), enc(&url)), None)?;
        let mut out: Vec<GroupMember> = v
            .as_object()
            .map(|o| o.iter().map(|(k, d)| GroupMember { name: k.clone(), proxy_type: String::new(), latency_ms: Some(d.as_i64().filter(|&x| x > 0).map(|x| x as i32).unwrap_or(-1)) }).collect())
            .unwrap_or_default();
        out.sort_by_key(|m| (m.latency_ms.map(|x| if x < 0 { i32::MAX } else { x }), m.name.clone()));
        Ok(out)
    }

    /// 活动连接（contract §8：最多 200 条最新）。
    pub fn active_connections(&self, limit: u32) -> Result<Vec<ConnectionInfo>, MobileError> {
        let mut v = self.connections_raw()?;
        v.sort_by_key(|c| std::cmp::Reverse(c.started_at));
        v.truncate(limit.min(200) as usize);
        Ok(v)
    }

    /// "最近连接"：按 host 聚合，最近活跃在前。
    pub fn recent_hosts(&self, limit: u32) -> Result<Vec<HostActivity>, MobileError> {
        Ok(aggregate_hosts(&self.connections_raw()?, limit.min(50) as usize))
    }

    /// 连接轨迹（contract §13）。host 当前无连接 → NotFound。
    pub fn host_trace(&self, host: String) -> Result<HostTrace, MobileError> {
        let raw = self.http.json("GET", "/connections", None)?;
        trace_from(&raw, &host)
    }

    pub fn close_connection(&self, id: String) -> Result<(), MobileError> {
        self.http.json("DELETE", &format!("/connections/{}", enc(&id)), None).map(|_| ())
    }

    pub fn close_all_connections(&self) -> Result<(), MobileError> {
        self.http.json("DELETE", "/connections", None).map(|_| ())
    }

    /// 模式切换（rule / global / direct）。
    pub fn set_mode(&self, mode: String) -> Result<(), MobileError> {
        let body = serde_json::json!({ "mode": mode }).to_string();
        self.http.json("PATCH", "/configs", Some(&body)).map(|_| ())
    }
}

impl MihomoClient {
    fn connections_raw(&self) -> Result<Vec<ConnectionInfo>, MobileError> {
        let v = self.http.json("GET", "/connections", None)?;
        Ok(v.get("connections").and_then(|c| c.as_array()).map(|a| a.iter().filter_map(conn_from).collect()).unwrap_or_default())
    }
}

pub fn aggregate_hosts(conns: &[ConnectionInfo], limit: usize) -> Vec<HostActivity> {
    let mut by: HashMap<&str, HostActivity> = HashMap::new();
    for c in conns {
        let e = by.entry(c.host.as_str()).or_insert_with(|| HostActivity { host: c.host.clone(), scene: c.scene.clone(), node: c.node.clone(), connections: 0, total_bytes: 0, last_seen_at: 0 });
        e.connections += 1;
        e.total_bytes += c.up_bytes + c.down_bytes;
        if c.started_at >= e.last_seen_at {
            e.last_seen_at = c.started_at;
            e.scene = c.scene.clone();
            e.node = c.node.clone();
        }
    }
    let mut v: Vec<HostActivity> = by.into_values().collect();
    v.sort_by(|a, b| b.last_seen_at.cmp(&a.last_seen_at).then(a.host.cmp(&b.host)));
    v.truncate(limit);
    v
}

pub fn trace_from(raw: &Value, host: &str) -> Result<HostTrace, MobileError> {
    let arr = raw.get("connections").and_then(|c| c.as_array()).cloned().unwrap_or_default();
    let mine: Vec<&Value> = arr.iter().filter(|v| conn_from(v).is_some_and(|c| c.host == host)).collect();
    let latest = mine.iter().max_by_key(|v| v.get("start").and_then(|s| s.as_str()).and_then(rfc3339_millis).unwrap_or(0)).ok_or_else(|| MobileError::NotFound(format!("host {host}")))?;
    let c = conn_from(latest).unwrap();
    let mut chain: Vec<String> = latest.get("chains").and_then(|c| c.as_array()).map(|a| a.iter().filter_map(|x| x.as_str().map(String::from)).collect()).unwrap_or_default();
    chain.reverse();
    let conns: Vec<ConnectionInfo> = mine.iter().filter_map(|v| conn_from(v)).collect();
    Ok(HostTrace {
        host: host.into(),
        last_seen_at: c.started_at,
        connections: conns.len() as i32,
        total_bytes: conns.iter().map(|c| c.up_bytes + c.down_bytes).sum(),
        rule: c.rule.clone(),
        chain,
        scene: c.scene.clone(),
        node: c.node.clone(),
    })
}

#[cfg(all(test, unix))]
mod tests {
    use super::*;
    use std::os::unix::net::UnixListener;

    const PROXIES: &str = r#"{"proxies":{
      "GLOBAL":{"type":"Selector","now":"AI","all":["AI","视频","节点选择"]},
      "AI":{"type":"Selector","now":"US Fixed IP","all":["US Fixed IP","新加坡 02"]},
      "视频":{"type":"URLTest","now":"香港 HKT","all":["香港 HKT"]},
      "节点选择":{"type":"Fallback","now":"新加坡 02","all":["新加坡 02","香港 HKT"]},
      "US Fixed IP":{"type":"Relay","all":["US-Fixed-01"]},
      "US-Fixed-01":{"type":"Vless","history":[{"time":"2026-11-06T09:40:00+08:00","delay":168}]},
      "新加坡 02":{"type":"Trojan","history":[{"time":"2026-11-06T09:41:00.5+08:00","delay":0}]},
      "香港 HKT":{"type":"Hysteria2","history":[]}
    }}"#;
    const CONNS: &str = r#"{"downloadTotal":1,"uploadTotal":1,"connections":[
      {"id":"c1","metadata":{"host":"claude.ai","destinationIP":"1.1.1.1","process":""},"upload":100,"download":1000,"start":"2026-11-06T09:41:00Z","chains":["US-Fixed-01","US Fixed IP","AI"],"rule":"DomainSuffix","rulePayload":"claude.ai"},
      {"id":"c2","metadata":{"host":"claude.ai","destinationIP":"1.1.1.1"},"upload":1,"download":9,"start":"2026-11-06T09:41:03Z","chains":["US-Fixed-01","US Fixed IP","AI"],"rule":"DomainSuffix","rulePayload":"claude.ai"},
      {"id":"c3","metadata":{"host":"","destinationIP":"36.1.2.3"},"upload":5,"download":5,"start":"2026-11-06T09:40:00Z","chains":["DIRECT"],"rule":"GeoIP","rulePayload":"CN"}
    ]}"#;

    fn serve(dir: &std::path::Path, n: usize) -> (String, std::thread::JoinHandle<Vec<String>>) {
        let p = dir.join("ctl.sock");
        let l = UnixListener::bind(&p).unwrap();
        let h = std::thread::spawn(move || {
            let mut seen = vec![];
            for _ in 0..n {
                let (mut s, _) = l.accept().unwrap();
                let mut buf = [0u8; 4096];
                let k = s.read(&mut buf).unwrap();
                let req = String::from_utf8_lossy(&buf[..k]).to_string();
                let line = req.lines().next().unwrap().to_string();
                let body = if line.contains("/proxies HTTP") {
                    PROXIES.to_string()
                } else if line.starts_with("GET /connections") {
                    CONNS.to_string()
                } else if line.contains("/delay") {
                    r#"{"新加坡 02":0,"US Fixed IP":168}"#.to_string()
                } else {
                    String::new()
                };
                // chunked，覆盖解析路径
                let resp = if body.is_empty() {
                    "HTTP/1.1 204 No Content\r\n\r\n".to_string()
                } else {
                    let (a, b) = body.split_at(body.len() / 2);
                    format!("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n{:x}\r\n{a}\r\n{:x}\r\n{b}\r\n0\r\n\r\n", a.len(), b.len())
                };
                s.write_all(resp.as_bytes()).unwrap();
                seen.push(req);
            }
            seen
        });
        (p.to_string_lossy().into(), h)
    }

    #[test]
    fn time_parse() {
        assert_eq!(rfc3339_millis("1970-01-01T00:00:00Z"), Some(0));
        assert_eq!(rfc3339_millis("2026-11-06T09:41:00+08:00"), Some(1_793_929_260_000));
        assert_eq!(rfc3339_millis("2026-11-06T01:41:00.123456789Z"), Some(1_793_929_260_123));
    }

    #[test]
    fn groups_members_trace_over_unix_socket() {
        let d = tempfile::tempdir().unwrap();
        let (sock, h) = serve(d.path(), 7);
        let c = MihomoClient::new(sock);
        let g = c.policy_groups().unwrap();
        assert_eq!(g.iter().map(|x| x.name.as_str()).collect::<Vec<_>>(), vec!["AI", "视频", "节点选择", "US Fixed IP"], "按 GLOBAL 顺序，其余在后");
        assert_eq!(g[0].group_type, GroupType::Select);
        assert_eq!(g[0].selected.as_deref(), Some("US Fixed IP"));
        assert_eq!(g[1].group_type, GroupType::UrlTest);
        assert_eq!(g[3].group_type, GroupType::Relay);
        assert_eq!(g[3].tested_at, Some(1_793_929_200_000));
        let m = c.group_members("节点选择".into(), 0, 10).unwrap();
        assert_eq!(m[0].latency_ms, Some(-1), "delay 0 = 超时");
        assert_eq!(m[1].latency_ms, None);
        let t = c.test_group("AI".into(), "https://www.gstatic.com/generate_204".into(), 3000).unwrap();
        assert_eq!(t.iter().map(|x| x.latency_ms.unwrap()).collect::<Vec<_>>(), vec![168, -1]);
        let hosts = c.recent_hosts(10).unwrap();
        assert_eq!(hosts[0].host, "claude.ai");
        assert_eq!((hosts[0].connections, hosts[0].total_bytes), (2, 1110));
        assert_eq!(hosts[1].host, "36.1.2.3");
        assert_eq!(hosts[1].scene, None);
        let tr = c.host_trace("claude.ai".into()).unwrap();
        assert_eq!(tr.rule, "DomainSuffix,claude.ai");
        assert_eq!(tr.chain, vec!["AI", "US Fixed IP", "US-Fixed-01"]);
        assert_eq!((tr.scene.as_deref(), tr.node.as_str()), (Some("AI"), "US-Fixed-01"));
        assert!(matches!(c.host_trace("nope.example".into()), Err(MobileError::NotFound(_))));
        c.select_in_group("AI".into(), "新加坡 02".into()).unwrap();
        let seen = h.join().unwrap();
        assert!(seen.last().unwrap().starts_with("PUT /proxies/AI HTTP/1.1"));
        assert!(seen.last().unwrap().ends_with(r#"{"name":"新加坡 02"}"#));
        assert!(seen.iter().any(|r| r.starts_with("GET /group/AI/delay?url=https%3A%2F%2Fwww.gstatic.com%2Fgenerate_204&timeout=3000")));
    }

    #[test]
    fn not_running_when_socket_missing() {
        let c = MihomoClient::new("/nonexistent/zm.sock".into());
        assert!(matches!(c.policy_groups(), Err(MobileError::NotRunning(_))));
    }
}
