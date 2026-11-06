//! 规则编译与测试（上亿条规则，mmap 只读）。
//!
//! 每层（覆写 / 订阅 / 各规则集）编译成一个文件：
//! - 域名（DOMAIN / DOMAIN-SUFFIX）：xxh3(kind ‖ 域名) 排序数组，16 B/条，二分查找。查询按标签逐级取后缀，O(标签数 · log n)。
//! - IPv4 / IPv6 CIDR：区间排序数组，二分查找。
//! - DOMAIN-KEYWORD：Aho-Corasick（条数少，常驻内存）。
//! 层内多条命中取原始序号最小者（与 Clash 自上而下一致）；层间按顺序，先命中先返回。
//! 文件只读 mmap，RAM 只占页缓存；iOS NE ~50 MB 上限下需真机验证（见 scale-architecture.md）。

use crate::error::MobileError;
use aho_corasick::AhoCorasick;
use memmap2::Mmap;
use std::fs::File;
use std::io::{BufWriter, Write};
use std::net::IpAddr;
use std::path::Path;
use std::time::Instant;

const MAGIC: &[u8; 8] = b"ZRULES01";
const DOM_SZ: usize = 16; // hash u64 | rule_no u32 | policy u16 | kind u8 | pad u8
const V4_SZ: usize = 20; // seg_start u32 | seg_end u32 | rule_start u32 | rule_no u32 | policy u16 | prefix u8 | pad
const V6_SZ: usize = 56; // seg_start u128 | seg_end u128 | rule_start u128 | rule_no u32 | policy u16 | prefix u8 | pad

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
#[repr(u8)]
pub enum DomainKind {
    Full = 1,
    Suffix = 2,
}

#[derive(Debug, Clone, PartialEq, uniffi::Enum)]
pub enum LayerKind {
    Override,
    Subscription,
    Domain,
    Ip,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct RuleLayerInfo {
    pub index: u32,
    pub kind: LayerKind,
    pub name: String,
    pub count: u64,
    pub note: String,
    pub disk_bytes: u64,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct RuleTrace {
    pub input: String,
    pub is_ip: bool,
    /// None = 落到 MATCH
    pub layer_index: Option<u32>,
    pub rule: String,
    pub rule_no: Option<u64>,
    pub policy: String,
    pub took_micros: u64,
}

/// 解析后的单条规则。
#[derive(Debug, Clone, PartialEq)]
pub enum Rule {
    Domain(String),
    DomainSuffix(String),
    DomainKeyword(String),
    IpCidr(u32, u8),
    IpCidr6(u128, u8),
}

/// 解析一行 Clash 规则：`TYPE,VALUE[,POLICY[,no-resolve]]`，或规则集纯文本行：`+.example.com` / `.example.com` / `example.com` / `1.2.3.0/24`。
/// 返回 (规则, 行内策略)。注释与空行返回 None。不支持的类型返回 None（计入 skipped）。
pub fn parse_line(line: &str) -> Option<(Rule, Option<String>)> {
    let l = line.trim().trim_start_matches("- ").trim().trim_matches(|c| c == '\'' || c == '"');
    if l.is_empty() || l.starts_with('#') || l.starts_with("//") || l == "payload:" {
        return None;
    }
    let parts: Vec<&str> = l.split(',').map(str::trim).collect();
    if parts.len() >= 2 {
        let policy = parts.get(2).map(|s| s.to_string());
        let v = parts[1].to_ascii_lowercase();
        let r = match parts[0].to_ascii_uppercase().as_str() {
            "DOMAIN" => Rule::Domain(v),
            "DOMAIN-SUFFIX" => Rule::DomainSuffix(v.trim_start_matches('.').to_string()),
            "DOMAIN-KEYWORD" => Rule::DomainKeyword(v),
            "IP-CIDR" | "IP-CIDR6" => parse_cidr(&v)?,
            _ => return None,
        };
        return Some((r, policy));
    }
    let v = l.to_ascii_lowercase();
    if v.contains('/') || v.parse::<IpAddr>().is_ok() {
        return parse_cidr(&v).map(|r| (r, None));
    }
    if let Some(s) = v.strip_prefix("+.") {
        return Some((Rule::DomainSuffix(s.to_string()), None));
    }
    if let Some(s) = v.strip_prefix('.') {
        return Some((Rule::DomainSuffix(s.to_string()), None));
    }
    if v.contains('.') && !v.contains(' ') {
        return Some((Rule::Domain(v), None));
    }
    None
}

fn parse_cidr(v: &str) -> Option<Rule> {
    let (ip, pre) = match v.split_once('/') {
        Some((a, b)) => (a, b.parse::<u8>().ok()),
        None => (v, None),
    };
    match ip.parse::<IpAddr>().ok()? {
        IpAddr::V4(a) => {
            let p = pre.unwrap_or(32).min(32);
            let mask = if p == 0 { 0 } else { u32::MAX << (32 - p) };
            Some(Rule::IpCidr(u32::from(a) & mask, p))
        }
        IpAddr::V6(a) => {
            let p = pre.unwrap_or(128).min(128);
            let mask = if p == 0 { 0 } else { u128::MAX << (128 - p) };
            Some(Rule::IpCidr6(u128::from(a) & mask, p))
        }
    }
}

fn dhash(kind: DomainKind, d: &str) -> u64 {
    let mut b = Vec::with_capacity(d.len() + 1);
    b.push(kind as u8);
    b.extend(d.as_bytes());
    xxhash_rust::xxh3::xxh3_64(&b)
}

/// 构建一层。
pub struct LayerBuilder {
    pub name: String,
    pub kind: LayerKind,
    pub note: String,
    policies: Vec<String>,
    default_policy: u16,
    dom: Vec<(u64, u32, u16, u8)>,
    v4: Vec<(u32, u32, u32, u16, u8)>,
    v6: Vec<(u128, u128, u32, u16, u8)>,
    kw: Vec<(String, u32, u16)>,
    next_no: u32,
    pub skipped: u64,
}

impl LayerBuilder {
    pub fn new(name: &str, kind: LayerKind, note: &str, default_policy: &str) -> Self {
        Self {
            name: name.into(),
            kind,
            note: note.into(),
            policies: vec![default_policy.to_string()],
            default_policy: 0,
            dom: vec![],
            v4: vec![],
            v6: vec![],
            kw: vec![],
            next_no: 1,
            skipped: 0,
        }
    }
    fn policy_ix(&mut self, p: Option<&str>) -> u16 {
        match p {
            None => self.default_policy,
            Some(p) => match self.policies.iter().position(|x| x == p) {
                Some(i) => i as u16,
                None => {
                    self.policies.push(p.to_string());
                    (self.policies.len() - 1) as u16
                }
            },
        }
    }
    pub fn add(&mut self, rule: Rule, policy: Option<&str>) {
        let pi = self.policy_ix(policy);
        let no = self.next_no;
        self.next_no += 1;
        match rule {
            Rule::Domain(d) => self.dom.push((dhash(DomainKind::Full, &d), no, pi, DomainKind::Full as u8)),
            Rule::DomainSuffix(d) => self.dom.push((dhash(DomainKind::Suffix, &d), no, pi, DomainKind::Suffix as u8)),
            Rule::DomainKeyword(k) => self.kw.push((k, no, pi)),
            Rule::IpCidr(a, p) => {
                let end = match p { 0 => u32::MAX, 32 => a, _ => a | (u32::MAX >> p) };
                self.v4.push((a, end, no, pi, p))
            }
            Rule::IpCidr6(a, p) => {
                let end = match p { 0 => u128::MAX, 128 => a, _ => a | (u128::MAX >> p) };
                self.v6.push((a, end, no, pi, p))
            }
        }
    }
    pub fn add_text(&mut self, text: &str) -> u64 {
        let mut n = 0;
        for line in text.lines() {
            match parse_line(line) {
                Some((r, p)) => {
                    self.add(r, p.as_deref());
                    n += 1;
                }
                None => {
                    let t = line.trim();
                    if !t.is_empty() && !t.starts_with('#') && t != "payload:" {
                        self.skipped += 1;
                    }
                }
            }
        }
        n
    }
    pub fn count(&self) -> u64 {
        (self.dom.len() + self.v4.len() + self.v6.len() + self.kw.len()) as u64
    }

    pub fn write(mut self, path: &Path) -> Result<u64, MobileError> {
        // 同哈希保留序号最小者
        self.dom.sort_unstable_by(|a, b| a.0.cmp(&b.0).then(a.1.cmp(&b.1)));
        self.dom.dedup_by_key(|e| e.0);
        let total = self.count();
        // CIDR 只有嵌套或不相交两种关系：编译期压平成不相交区段，每段带层内序号最小的规则。查询一次二分。
        let v4 = flatten(std::mem::take(&mut self.v4));
        let v6 = flatten(std::mem::take(&mut self.v6));
        let f = File::create(path)?;
        let mut w = BufWriter::with_capacity(1 << 20, f);
        w.write_all(MAGIC)?;
        put_str(&mut w, &self.name)?;
        put_str(&mut w, &self.note)?;
        w.write_all(&[match self.kind {
            LayerKind::Override => 0,
            LayerKind::Subscription => 1,
            LayerKind::Domain => 2,
            LayerKind::Ip => 3,
        }])?;
        w.write_all(&total.to_le_bytes())?;
        w.write_all(&(self.policies.len() as u32).to_le_bytes())?;
        for p in &self.policies {
            put_str(&mut w, p)?;
        }
        w.write_all(&(self.kw.len() as u32).to_le_bytes())?;
        for (k, no, p) in &self.kw {
            put_str(&mut w, k)?;
            w.write_all(&no.to_le_bytes())?;
            w.write_all(&p.to_le_bytes())?;
        }
        // 对齐到 16 字节，便于 mmap 后按定长读取
        w.write_all(&(self.dom.len() as u64).to_le_bytes())?;
        w.write_all(&(v4.len() as u64).to_le_bytes())?;
        w.write_all(&(v6.len() as u64).to_le_bytes())?;
        for (h, no, p, k) in &self.dom {
            w.write_all(&h.to_le_bytes())?;
            w.write_all(&no.to_le_bytes())?;
            w.write_all(&p.to_le_bytes())?;
            w.write_all(&[*k, 0])?;
        }
        for g in &v4 {
            w.write_all(&g.s.to_le_bytes())?;
            w.write_all(&g.e.to_le_bytes())?;
            w.write_all(&g.rs.to_le_bytes())?;
            w.write_all(&g.no.to_le_bytes())?;
            w.write_all(&g.policy.to_le_bytes())?;
            w.write_all(&[g.prefix, 0])?;
        }
        for g in &v6 {
            w.write_all(&g.s.to_le_bytes())?;
            w.write_all(&g.e.to_le_bytes())?;
            w.write_all(&g.rs.to_le_bytes())?;
            w.write_all(&g.no.to_le_bytes())?;
            w.write_all(&g.policy.to_le_bytes())?;
            w.write_all(&[g.prefix, 0])?;
        }
        w.flush()?;
        Ok(total)
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
struct Seg<T> {
    s: T,
    e: T,
    rs: T,
    no: u32,
    policy: u16,
    prefix: u8,
}

trait Addr: Copy + Ord + std::fmt::Debug {
    const MAX: Self;
    fn inc(self) -> Self;
    fn dec(self) -> Self;
}
impl Addr for u32 {
    const MAX: Self = u32::MAX;
    fn inc(self) -> Self { self.wrapping_add(1) }
    fn dec(self) -> Self { self.wrapping_sub(1) }
}
impl Addr for u128 {
    const MAX: Self = u128::MAX;
    fn inc(self) -> Self { self.wrapping_add(1) }
    fn dec(self) -> Self { self.wrapping_sub(1) }
}

/// 嵌套/不相交区间 → 不相交区段（每段取序号最小的覆盖规则）。O(n log n)。
fn flatten<T: Addr>(mut v: Vec<(T, T, u32, u16, u8)>) -> Vec<Seg<T>> {
    v.sort_unstable_by(|a, b| a.0.cmp(&b.0).then(b.1.cmp(&a.1)).then(a.2.cmp(&b.2)));
    // 栈元素：(区间, 栈内最优规则)
    let mut stack: Vec<((T, T), Seg<T>)> = Vec::new();
    let mut out: Vec<Seg<T>> = Vec::new();
    let mut pos: Option<T> = None; // 下一个待输出位置
    let emit = |out: &mut Vec<Seg<T>>, s: T, e: T, best: &Seg<T>| {
        if s > e { return; }
        if let Some(last) = out.last_mut() {
            if last.no == best.no && last.e.inc() == s && last.e != T::MAX {
                last.e = e;
                return;
            }
        }
        out.push(Seg { s, e, ..*best });
    };
    let pop_until = |stack: &mut Vec<((T, T), Seg<T>)>, out: &mut Vec<Seg<T>>, pos: &mut Option<T>, upto: Option<T>| {
        while let Some(&((_, end), best)) = stack.last() {
            if let Some(u) = upto { if end >= u { break; } }
            if let Some(p) = *pos { emit(out, p, end, &best); }
            stack.pop();
            *pos = if end == T::MAX { None } else { Some(end.inc()) };
            if pos.is_none() { stack.clear(); }
        }
    };
    for (s, e, no, policy, prefix) in v {
        pop_until(&mut stack, &mut out, &mut pos, Some(s));
        if let Some(&(_, best)) = stack.last() {
            if let Some(p) = pos { if p < s { emit(&mut out, p, s.dec(), &best); } }
        }
        let me = Seg { s, e, rs: s, no, policy, prefix };
        let best = match stack.last() { Some(&(_, b)) if b.no < no => b, _ => me };
        stack.push(((s, e), best));
        pos = Some(s);
    }
    pop_until(&mut stack, &mut out, &mut pos, None);
    out
}

fn put_str(w: &mut impl Write, s: &str) -> std::io::Result<()> {
    let b = s.as_bytes();
    w.write_all(&(b.len() as u32).to_le_bytes())?;
    w.write_all(b)
}

pub struct Layer {
    map: Mmap,
    pub name: String,
    pub note: String,
    pub kind: LayerKind,
    pub count: u64,
    policies: Vec<String>,
    kw: Option<(AhoCorasick, Vec<(String, u32, u16)>)>,
    dom_off: usize,
    dom_n: usize,
    v4_off: usize,
    v4_n: usize,
    v6_off: usize,
    v6_n: usize,
    pub disk_bytes: u64,
}

struct Rd<'a>(&'a [u8], usize);
impl<'a> Rd<'a> {
    fn take(&mut self, n: usize) -> Result<&'a [u8], MobileError> {
        if self.1 + n > self.0.len() {
            return Err(MobileError::Corrupt("规则文件截断".into()));
        }
        self.1 += n;
        Ok(&self.0[self.1 - n..self.1])
    }
    fn u32(&mut self) -> Result<u32, MobileError> {
        Ok(u32::from_le_bytes(self.take(4)?.try_into().unwrap()))
    }
    fn u64(&mut self) -> Result<u64, MobileError> {
        Ok(u64::from_le_bytes(self.take(8)?.try_into().unwrap()))
    }
    fn s(&mut self) -> Result<String, MobileError> {
        let n = self.u32()? as usize;
        Ok(String::from_utf8_lossy(self.take(n)?).into_owned())
    }
}

#[derive(Clone, Copy)]
struct Hit {
    no: u32,
    policy: u16,
}

impl Layer {
    pub fn open(path: &Path) -> Result<Self, MobileError> {
        let f = File::open(path)?;
        let disk_bytes = f.metadata()?.len();
        // SAFETY: 只读打开本库写出的文件。
        let map = unsafe { Mmap::map(&f)? };
        #[cfg(unix)]
        {
            let _ = map.advise(memmap2::Advice::Random);
        }
        let mut r = Rd(&map, 0);
        if r.take(8)? != MAGIC {
            return Err(MobileError::Corrupt("不是规则文件".into()));
        }
        let name = r.s()?;
        let note = r.s()?;
        let kind = match r.take(1)?[0] {
            0 => LayerKind::Override,
            1 => LayerKind::Subscription,
            2 => LayerKind::Domain,
            _ => LayerKind::Ip,
        };
        let count = r.u64()?;
        let np = r.u32()? as usize;
        let mut policies = Vec::with_capacity(np);
        for _ in 0..np {
            policies.push(r.s()?);
        }
        let nk = r.u32()? as usize;
        let mut kws = Vec::with_capacity(nk);
        for _ in 0..nk {
            let k = r.s()?;
            let no = r.u32()?;
            let p = u16::from_le_bytes(r.take(2)?.try_into().unwrap());
            kws.push((k, no, p));
        }
        let kw = if kws.is_empty() {
            None
        } else {
            let ac = AhoCorasick::new(kws.iter().map(|k| k.0.as_str())).map_err(|e| MobileError::Corrupt(e.to_string()))?;
            Some((ac, kws))
        };
        let dom_n = r.u64()? as usize;
        let v4_n = r.u64()? as usize;
        let v6_n = r.u64()? as usize;
        let dom_off = r.1;
        r.take(dom_n * DOM_SZ)?;
        let v4_off = r.1;
        r.take(v4_n * V4_SZ)?;
        let v6_off = r.1;
        r.take(v6_n * V6_SZ)?;
        Ok(Self { map, name, note, kind, count, policies, kw, dom_off, dom_n, v4_off, v4_n, v6_off, v6_n, disk_bytes })
    }

    fn dom_at(&self, i: usize) -> (u64, u32, u16) {
        let b = &self.map[self.dom_off + i * DOM_SZ..self.dom_off + (i + 1) * DOM_SZ];
        (u64::from_le_bytes(b[0..8].try_into().unwrap()), u32::from_le_bytes(b[8..12].try_into().unwrap()), u16::from_le_bytes([b[12], b[13]]))
    }

    fn find_hash(&self, h: u64) -> Option<Hit> {
        let (mut lo, mut hi) = (0usize, self.dom_n);
        while lo < hi {
            let m = (lo + hi) / 2;
            let (mh, no, p) = self.dom_at(m);
            match mh.cmp(&h) {
                std::cmp::Ordering::Less => lo = m + 1,
                std::cmp::Ordering::Greater => hi = m,
                std::cmp::Ordering::Equal => return Some(Hit { no, policy: p }),
            }
        }
        None
    }

    /// 返回 (命中, 规则文本)
    fn match_domain(&self, d: &str) -> Option<(Hit, String)> {
        let mut best: Option<(Hit, String)> = None;
        let mut consider = |h: Hit, text: String| {
            if best.as_ref().map(|(b, _)| h.no < b.no).unwrap_or(true) {
                best = Some((h, text));
            }
        };
        if self.dom_n > 0 {
            if let Some(h) = self.find_hash(dhash(DomainKind::Full, d)) {
                consider(h, format!("DOMAIN,{d}"));
            }
            let mut s = d;
            loop {
                if let Some(h) = self.find_hash(dhash(DomainKind::Suffix, s)) {
                    consider(h, format!("DOMAIN-SUFFIX,{s}"));
                }
                match s.find('.') {
                    Some(i) => s = &s[i + 1..],
                    None => break,
                }
            }
        }
        if let Some((ac, kws)) = &self.kw {
            for m in ac.find_overlapping_iter(d) {
                let (k, no, p) = &kws[m.pattern().as_usize()];
                consider(Hit { no: *no, policy: *p }, format!("DOMAIN-KEYWORD,{k}"));
            }
        }
        best
    }

    fn match_v4(&self, ip: u32) -> Option<(Hit, String)> {
        let at = |i: usize| {
            let b = &self.map[self.v4_off + i * V4_SZ..self.v4_off + (i + 1) * V4_SZ];
            let u = |o: usize| u32::from_le_bytes(b[o..o + 4].try_into().unwrap());
            (u(0), u(4), u(8), u(12), u16::from_le_bytes([b[16], b[17]]), b[18])
        };
        let (mut lo, mut hi) = (0usize, self.v4_n);
        while lo < hi {
            let m = (lo + hi) / 2;
            if at(m).0 <= ip { lo = m + 1 } else { hi = m }
        }
        if lo == 0 { return None; }
        let (_, e, rs, no, p, pre) = at(lo - 1);
        (ip <= e).then(|| (Hit { no, policy: p }, format!("IP-CIDR,{}/{}", std::net::Ipv4Addr::from(rs), pre)))
    }

    fn match_v6(&self, ip: u128) -> Option<(Hit, String)> {
        let at = |i: usize| {
            let b = &self.map[self.v6_off + i * V6_SZ..self.v6_off + (i + 1) * V6_SZ];
            let u = |o: usize| u128::from_le_bytes(b[o..o + 16].try_into().unwrap());
            (u(0), u(16), u(32), u32::from_le_bytes(b[48..52].try_into().unwrap()), u16::from_le_bytes([b[52], b[53]]), b[54])
        };
        let (mut lo, mut hi) = (0usize, self.v6_n);
        while lo < hi {
            let m = (lo + hi) / 2;
            if at(m).0 <= ip { lo = m + 1 } else { hi = m }
        }
        if lo == 0 { return None; }
        let (_, e, rs, no, p, pre) = at(lo - 1);
        (ip <= e).then(|| (Hit { no, policy: p }, format!("IP-CIDR6,{}/{}", std::net::Ipv6Addr::from(rs), pre)))
    }

    pub fn info(&self, index: u32) -> RuleLayerInfo {
        RuleLayerInfo { index, kind: self.kind.clone(), name: self.name.clone(), count: self.count, note: self.note.clone(), disk_bytes: self.disk_bytes }
    }
}

#[derive(Default)]
pub struct RuleSet {
    pub layers: Vec<Layer>,
    pub final_policy: String,
}

pub fn normalize_domain(input: &str) -> Result<String, MobileError> {
    let mut s = input.trim().to_ascii_lowercase();
    for p in ["https://", "http://"] {
        if let Some(r) = s.strip_prefix(p) {
            s = r.to_string();
        }
    }
    if let Some(i) = s.find(['/', '?', '#']) {
        s.truncate(i);
    }
    if let Some(i) = s.rfind(':') {
        if !s.contains('[') && s.matches(':').count() == 1 {
            s.truncate(i);
        }
    }
    let s = s.trim_end_matches('.').to_string();
    if s.is_empty() || s.len() > 253 || s.contains(' ') {
        return Err(MobileError::RuleInputInvalid(input.into()));
    }
    Ok(s)
}

impl RuleSet {
    pub fn total(&self) -> u64 {
        self.layers.iter().map(|l| l.count).sum()
    }
    pub fn disk_bytes(&self) -> u64 {
        self.layers.iter().map(|l| l.disk_bytes).sum()
    }

    pub fn test(&self, input: &str) -> Result<RuleTrace, MobileError> {
        let t0 = Instant::now();
        let raw = input.trim().trim_start_matches('[').trim_end_matches(']');
        let ip: Option<IpAddr> = raw.parse().ok();
        let d = if ip.is_none() { Some(normalize_domain(input)?) } else { None };
        for (li, l) in self.layers.iter().enumerate() {
            let hit = match (&ip, &d) {
                (Some(IpAddr::V4(a)), _) => l.match_v4(u32::from(*a)),
                (Some(IpAddr::V6(a)), _) => l.match_v6(u128::from(*a)),
                (None, Some(d)) => l.match_domain(d),
                _ => None,
            };
            if let Some((h, text)) = hit {
                return Ok(RuleTrace {
                    input: input.to_string(),
                    is_ip: ip.is_some(),
                    layer_index: Some(li as u32),
                    rule: text,
                    rule_no: Some(h.no as u64),
                    policy: l.policies.get(h.policy as usize).cloned().unwrap_or_default(),
                    took_micros: t0.elapsed().as_micros() as u64,
                });
            }
        }
        Ok(RuleTrace {
            input: input.to_string(),
            is_ip: ip.is_some(),
            layer_index: None,
            rule: "MATCH".into(),
            rule_no: None,
            policy: self.final_policy.clone(),
            took_micros: t0.elapsed().as_micros() as u64,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn build(dir: &Path, name: &str, kind: LayerKind, policy: &str, text: &str) -> Layer {
        let mut b = LayerBuilder::new(name, kind, "", policy);
        b.add_text(text);
        let p = dir.join(format!("{name}.zr"));
        b.write(&p).unwrap();
        Layer::open(&p).unwrap()
    }

    #[test]
    fn layered_matching_follows_prototype() {
        let d = tempfile::tempdir().unwrap();
        let rs = RuleSet {
            layers: vec![
                build(d.path(), "覆写", LayerKind::Override, "DIRECT", "DOMAIN-SUFFIX,github.com,DIRECT"),
                build(d.path(), "订阅", LayerKind::Subscription, "video", "DOMAIN-SUFFIX,netflix.com,video\nDOMAIN-SUFFIX,nflxvideo.net,video\nMATCH,other"),
                build(d.path(), "OpenAI", LayerKind::Domain, "ai", "payload:\n  - '+.openai.com'\n  - '+.chatgpt.com'\n  - '+.claude.ai'\n  - '+.anthropic.com'"),
                build(d.path(), "广告与跟踪", LayerKind::Domain, "REJECT", "DOMAIN-KEYWORD,doubleclick\nDOMAIN-KEYWORD,adservice\n+.ads.example.com"),
                build(d.path(), "geoip:cn", LayerKind::Ip, "DIRECT", "36.0.0.0/10\n1.0.1.0/24\n2001:db8::/32"),
            ],
            final_policy: "other".into(),
        };
        let t = |q: &str| rs.test(q).unwrap();
        assert_eq!(t("api.github.com").layer_index, Some(0));
        assert_eq!(t("api.github.com").rule, "DOMAIN-SUFFIX,github.com");
        assert_eq!(t("netflix.com").policy, "video");
        assert_eq!(t("https://chatgpt.com/c/123").policy, "ai");
        assert_eq!(t("ad.doubleclick.net").policy, "REJECT");
        assert_eq!(t("ad.doubleclick.net").rule, "DOMAIN-KEYWORD,doubleclick");
        assert_eq!(t("x.ads.example.com").layer_index, Some(3));
        assert_eq!(t("36.1.2.3").layer_index, Some(4));
        assert_eq!(t("36.1.2.3").rule, "IP-CIDR,36.0.0.0/10");
        assert_eq!(t("2001:db8::1").policy, "DIRECT");
        assert_eq!(t("8.8.8.8").rule, "MATCH");
        assert_eq!(t("example.org").policy, "other");
        assert!(rs.test("bad domain").is_err());
    }

    #[test]
    fn nested_cidr_picks_first_rule() {
        let d = tempfile::tempdir().unwrap();
        let l = build(d.path(), "ip", LayerKind::Ip, "A", "IP-CIDR,10.0.0.0/8,A\nIP-CIDR,10.1.0.0/16,B");
        let rs = RuleSet { layers: vec![l], final_policy: "F".into() };
        assert_eq!(rs.test("10.1.2.3").unwrap().policy, "A");
        assert_eq!(rs.test("10.2.0.1").unwrap().policy, "A");
        assert_eq!(rs.test("11.0.0.1").unwrap().policy, "F");
    }

    #[test]
    fn flatten_prefers_lowest_rule_number() {
        // 外层序号大、内层序号小：内层区段取内层，外层其余部分取外层
        let segs = flatten(vec![(0u32, 255, 5, 0, 24), (16, 31, 2, 1, 28), (100, 100, 9, 2, 32)]);
        let probe = |ip: u32| segs.iter().find(|g| g.s <= ip && ip <= g.e).map(|g| g.no);
        assert_eq!(probe(0), Some(5));
        assert_eq!(probe(20), Some(2));
        assert_eq!(probe(32), Some(5));
        assert_eq!(probe(100), Some(5));
        assert_eq!(probe(255), Some(5));
        assert_eq!(probe(256), None);
        // 不相交、全空间
        let segs = flatten(vec![(0u32, u32::MAX, 3, 0, 0), (10, 10, 1, 0, 32)]);
        assert_eq!(segs.len(), 3);
    }
}
