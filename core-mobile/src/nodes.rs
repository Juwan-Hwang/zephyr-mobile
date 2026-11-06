//! 千万级节点存储与检索。
//!
//! 设计（见 design/notes/scale-architecture.md）：
//! - 记录按地区连续排列，地区分区 = 连续区间，分区偏移 O(1)。
//! - 定长记录（24 B）+ 字符串表，写成单文件后 mmap 打开，常驻内存只有页缓存。
//! - 属性倒排：地区 / 城市 / 运营商 / 标签 / 协议 / 名称词元 → RoaringBitmap（压缩位图）。
//! - 查询 = 每个词的候选位图取交集；分页用 rank/select，任何查询都不扫全表。
//! - NodeId = 指纹（server+port+protocol 的 xxh3），跨订阅更新稳定。

use crate::error::MobileError;
use memmap2::Mmap;
use roaring::RoaringBitmap;
use std::collections::{BTreeMap, HashMap};
use std::fs::File;
use std::io::{BufWriter, Write};
use std::path::Path;
use std::time::Instant;

pub const MAGIC: &[u8; 8] = b"ZNODES01";
pub const RECORD_SIZE: usize = 24;
pub const MAX_PAGE: u32 = 500;

/// 待写入的节点（解析订阅后得到）。
#[derive(Debug, Clone, PartialEq)]
pub struct NodeInput {
    pub name: String,
    pub server: String,
    pub port: u16,
    pub protocol: String,
    /// ISO 3166 alpha-2；未知用 "ZZ"
    pub region: String,
    pub city: Option<String>,
    pub carrier: Option<String>,
    pub tag: Option<String>,
    /// 倍率 ×10（15 = ×1.5）；0 = 无
    pub multiplier_x10: u8,
    pub subscription: u16,
}

pub fn fingerprint(server: &str, port: u16, protocol: &str) -> u64 {
    // 小写 + 去空白后哈希；常见长度走栈缓冲，零分配（建库热点）
    let (s, p) = (server.trim(), protocol.trim());
    let n = s.len() + p.len() + 4;
    let mut stack = [0u8; 256];
    let mut heap;
    let buf: &mut [u8] = if n <= stack.len() {
        &mut stack[..n]
    } else {
        heap = vec![0u8; n];
        &mut heap[..]
    };
    let mut k = 0;
    for &b in s.as_bytes() {
        buf[k] = b.to_ascii_lowercase();
        k += 1;
    }
    buf[k] = 0;
    buf[k + 1..k + 3].copy_from_slice(&port.to_le_bytes());
    buf[k + 3] = 0;
    k += 4;
    for &b in p.as_bytes() {
        buf[k] = b.to_ascii_lowercase();
        k += 1;
    }
    xxhash_rust::xxh3::xxh3_64(&buf[..k])
}

/// 一行查询结果。
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct NodeRow {
    pub id: u64,
    pub name: String,
    pub region: String,
    pub city: Option<String>,
    pub carrier: Option<String>,
    pub tag: Option<String>,
    pub protocol: String,
    pub multiplier: Option<f32>,
    pub subscription: u16,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct RegionSection {
    pub region: String,
    pub count: u64,
    /// 结果集虚拟列表中的行偏移（含之前各分区的头行）
    pub row_offset: u64,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct NodeQueryResult {
    pub query: String,
    pub total: u64,
    pub sections: Vec<RegionSection>,
    pub highlights: Vec<String>,
    pub took_micros: u64,
    pub token: u64,
}

// ---------- 文件格式 ----------
// [MAGIC 8][version u32][count u32]
// [dict_len u32][dict: u32 count, each (u16 len, bytes)]      字符串字典（地区/城市/运营商/标签/协议 共用）
// [regions: u32 n, each (u32 dict_id, u32 start, u32 len)]
// [records: count * 24]
// [names: u32 bytes len, bytes]
// [index: u32 n, each (u8 kind, u32 key_dict_or_token, u32 bitmap_len, bitmap bytes)]
// [tokens: u32 n, each (u16 len, bytes)]                      名称词元字典（排序后，支持前缀）
//
// record (24 B, LE): fp u64 | name_off u32 | name_len u16 | sub u16 | city u16 | carrier u16 | tag u8 | proto u8 | mult u8 | region_ix u8
// city / carrier / tag / proto 存 dict id（u16，0xFFFF/0xFF = 无）

#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug, PartialOrd, Ord)]
#[repr(u8)]
enum IndexKind {
    Region = 0,
    City = 1,
    Carrier = 2,
    Tag = 3,
    Protocol = 4,
    NameToken = 5,
}

/// 流式建库：push 时立即压成 24 B 记录 + 名称字节，不保留 NodeInput。
/// 1310 万节点峰值内存 ≈ 记录 315 MB + 名称 ~330 MB + 去重临时 210 MB（原实现 2.7 GB 会被 OOM 杀掉）。
/// 建库阶段（进度回调用）。
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum BuildPhase {
    /// 解析订阅 / 生成节点；total = 0 表示总数未知
    Parse,
    /// 建倒排索引
    Index,
    /// 写文件
    Write,
}

pub struct NodeStoreBuilder {
    records: Vec<[u8; RECORD_SIZE]>,
    names: Vec<u8>,
    dict: Vec<String>,
    dict_ix: rustc_hash::FxHashMap<String, u32>,
    /// push 顺序的地区表：(dict id, 计数)
    regions: Vec<(u32, u32)>,
    region_ix: rustc_hash::FxHashMap<String, u8>,
    error: Option<MobileError>,
}

impl Default for NodeStoreBuilder {
    fn default() -> Self {
        Self::new()
    }
}

impl NodeStoreBuilder {
    pub fn new() -> Self {
        Self::with_capacity(0)
    }
    pub fn with_capacity(n: usize) -> Self {
        let mut b = Self {
            records: Vec::with_capacity(n),
            names: Vec::with_capacity(n * 24),
            dict: Vec::new(),
            dict_ix: Default::default(),
            regions: Vec::new(),
            region_ix: Default::default(),
            error: None,
        };
        // 标签与协议存 u8：先占低位 id，保证城市/运营商再多也不会把它们挤出 255
        for t in crate::mock::TAGS.iter().chain(["VLESS", "VMess", "Hy2", "Hysteria", "TUIC", "SS", "SSR", "Trojan", "WireGuard", "AnyTLS", "Snell", "HTTP", "SOCKS5"].iter()) {
            b.intern(t);
        }
        b
    }
    fn intern(&mut self, s: &str) -> u32 {
        if let Some(&i) = self.dict_ix.get(s) {
            return i;
        }
        let i = self.dict.len() as u32;
        self.dict.push(s.to_string());
        self.dict_ix.insert(s.to_string(), i);
        i
    }
    pub fn push(&mut self, n: NodeInput) {
        if self.error.is_some() {
            return;
        }
        let rix = match self.region_ix.get(&n.region) {
            Some(&r) => r,
            None => {
                if self.regions.len() >= 255 {
                    self.error = Some(MobileError::Invalid("超过 255 个地区".into()));
                    return;
                }
                let d = self.intern(&n.region);
                self.regions.push((d, 0));
                let r = (self.regions.len() - 1) as u8;
                self.region_ix.insert(n.region.clone(), r);
                r
            }
        };
        self.regions[rix as usize].1 += 1;
        let city = match &n.city { Some(s) if !s.is_empty() => self.intern(s) as u16, _ => u16::MAX };
        let carrier = match &n.carrier { Some(s) if !s.is_empty() => self.intern(s) as u16, _ => u16::MAX };
        let tag = match &n.tag { Some(s) if !s.is_empty() => self.intern(s), _ => u8::MAX as u32 };
        let proto = self.intern(&n.protocol);
        if tag > u8::MAX as u32 || proto >= u8::MAX as u32 {
            self.error = Some(MobileError::Invalid("标签或协议种类超过 254".into()));
            return;
        }
        let (tag, proto) = (tag as u8, proto as u8);
        if self.dict.len() > 250 * 255 {
            self.error = Some(MobileError::Invalid("属性字典过大".into()));
            return;
        }
        let fp = fingerprint(&n.server, n.port, &n.protocol);
        let name_off = self.names.len() as u32;
        let nb = n.name.as_bytes();
        let name_len = nb.len().min(u16::MAX as usize) as u16;
        self.names.extend_from_slice(&nb[..name_len as usize]);
        let mut r = [0u8; RECORD_SIZE];
        r[0..8].copy_from_slice(&fp.to_le_bytes());
        r[8..12].copy_from_slice(&name_off.to_le_bytes());
        r[12..14].copy_from_slice(&name_len.to_le_bytes());
        r[14..16].copy_from_slice(&n.subscription.to_le_bytes());
        r[16..18].copy_from_slice(&city.to_le_bytes());
        r[18..20].copy_from_slice(&carrier.to_le_bytes());
        r[20] = tag;
        r[21] = proto;
        r[22] = n.multiplier_x10;
        r[23] = rix;
        self.records.push(r);
    }
    pub fn len(&self) -> usize {
        self.records.len()
    }
    pub fn is_empty(&self) -> bool {
        self.records.is_empty()
    }

    /// 写出到文件。同指纹去重（保留先出现的）。地区按节点数降序排列（与原型一致：大地区在前），地区内保持输入顺序。
    pub fn write(self, path: &Path) -> Result<u32, MobileError> {
        self.write_with_progress(path, &|_, _, _| true)
    }

    /// progress(phase, done, total) 返回 false 取消（MobileError::Cancelled）。phase：Index / Write。
    pub fn write_with_progress(self, path: &Path, progress: &dyn Fn(BuildPhase, u64, u64) -> bool) -> Result<u32, MobileError> {
        if let Some(e) = self.error {
            return Err(e);
        }
        let NodeStoreBuilder { records, names, dict, mut regions, .. } = self;
        let prof = std::env::var_os("ZM_PROFILE").is_some();
        let t0 = Instant::now();
        let lap = |what: &str| if prof { eprintln!("  write.{what}: {:?}", t0.elapsed()) };
        let n = records.len();
        // 去重：按 (fp, 下标) 排序，同 fp 的后来者作废
        let mut dup = vec![false; n];
        {
            let mut fps: Vec<(u64, u32)> = records.iter().enumerate().map(|(i, r)| (u64::from_le_bytes(r[0..8].try_into().unwrap()), i as u32)).collect();
            fps.sort_unstable();
            for w in fps.windows(2) {
                if w[0].0 == w[1].0 {
                    dup[w[1].1 as usize] = true;
                }
            }
        }
        for (i, r) in records.iter().enumerate() {
            if dup[i] {
                regions[r[23] as usize].1 -= 1;
            }
        }
        // 地区最终顺序
        let mut order_r: Vec<usize> = (0..regions.len()).filter(|&i| regions[i].1 > 0).collect();
        order_r.sort_by(|&a, &b| regions[b].1.cmp(&regions[a].1).then(dict[regions[a].0 as usize].cmp(&dict[regions[b].0 as usize])));
        let mut final_ix = vec![u8::MAX; regions.len()];
        let mut starts = Vec::with_capacity(order_r.len());
        let mut acc = 0u32;
        for (fi, &ri) in order_r.iter().enumerate() {
            final_ix[ri] = fi as u8;
            starts.push(acc);
            acc += regions[ri].1;
        }
        let count = acc;
        // 计数排序得到写出顺序
        let mut cursor = starts.clone();
        let mut perm = vec![0u32; count as usize];
        for (i, r) in records.iter().enumerate() {
            if dup[i] {
                continue;
            }
            let f = final_ix[r[23] as usize] as usize;
            perm[cursor[f] as usize] = i as u32;
            cursor[f] += 1;
        }
        drop(dup);
        drop(cursor);
        lap("dedup+order");

        // 稠密数组代替 BTreeMap：每节点 5+ 次查找是建库热点（2.6M 节点 4.9 s → 见 docs/perf.md）
        let nd = dict.len();
        let mut attr: [Vec<Option<BmAcc>>; 5] = std::array::from_fn(|_| (0..nd).map(|_| None).collect());
        let mut tokens: Vec<String> = Vec::new();
        let mut tok_bm: Vec<BmAcc> = Vec::new();
        let mut token_ix: rustc_hash::FxHashMap<String, u32> = Default::default();
        // 原始片段 → 词元 id（None = 过滤掉）。名称高度重复，缓存命中后零分配。
        let mut raw_cache: rustc_hash::FxHashMap<&str, Option<u32>> = Default::default();
        let mut ids: Vec<u32> = Vec::with_capacity(8);
        fn put(v: &mut [Option<BmAcc>], k: usize, i: u32) {
            v[k].get_or_insert_with(BmAcc::default).push(i);
        }
        let total = perm.len() as u64;
        for (pos, &src) in perm.iter().enumerate() {
            if pos & 0xFFFF == 0 && !progress(BuildPhase::Index, pos as u64, total) {
                return Err(MobileError::Cancelled);
            }
            let i = pos as u32;
            let r = &records[src as usize];
            let rix = final_ix[r[23] as usize] as usize;
            put(&mut attr[IndexKind::Region as usize], regions[order_r[rix]].0 as usize, i);
            let city = u16::from_le_bytes([r[16], r[17]]);
            let carrier = u16::from_le_bytes([r[18], r[19]]);
            if city != u16::MAX {
                put(&mut attr[IndexKind::City as usize], city as usize, i);
            }
            if carrier != u16::MAX {
                put(&mut attr[IndexKind::Carrier as usize], carrier as usize, i);
            }
            if r[20] != u8::MAX {
                put(&mut attr[IndexKind::Tag as usize], r[20] as usize, i);
            }
            put(&mut attr[IndexKind::Protocol as usize], r[21] as usize, i);
            let off = u32::from_le_bytes(r[8..12].try_into().unwrap()) as usize;
            let len = u16::from_le_bytes([r[12], r[13]]) as usize;
            let name = std::str::from_utf8(&names[off..off + len]).unwrap_or("");
            ids.clear();
            for raw in name.split(is_token_sep) {
                let id = match raw_cache.get(raw) {
                    Some(&x) => x,
                    None => {
                        let x = normalize_token(raw).map(|t| match token_ix.get(&t) {
                            Some(&id) => id,
                            None => {
                                tokens.push(t.clone());
                                tok_bm.push(BmAcc::default());
                                let id = (tokens.len() - 1) as u32;
                                token_ix.insert(t, id);
                                id
                            }
                        });
                        raw_cache.insert(raw, x);
                        x
                    }
                };
                if let Some(id) = id {
                    ids.push(id);
                }
            }
            ids.sort_unstable();
            ids.dedup();
            for &id in &ids {
                tok_bm[id as usize].push(i);
            }
        }
        drop(token_ix);
        drop(raw_cache);
        lap("index");
        let mut index: BTreeMap<(IndexKind, u32), RoaringBitmap> = BTreeMap::new();
        for (k, kind) in [IndexKind::Region, IndexKind::City, IndexKind::Carrier, IndexKind::Tag, IndexKind::Protocol].into_iter().enumerate() {
            for (key, bm) in std::mem::take(&mut attr[k]).into_iter().enumerate() {
                if let Some(bm) = bm {
                    index.insert((kind, key as u32), bm.finish());
                }
            }
        }
        for (id, bm) in tok_bm.into_iter().enumerate() {
            index.insert((IndexKind::NameToken, id as u32), bm.finish());
        }

        // 词元字典排序（前缀查找），并重映射 id
        let mut order: Vec<u32> = (0..tokens.len() as u32).collect();
        order.sort_by(|&a, &b| tokens[a as usize].cmp(&tokens[b as usize]));
        let mut remap = vec![0u32; tokens.len()];
        for (new, &old) in order.iter().enumerate() {
            remap[old as usize] = new as u32;
        }
        let index: BTreeMap<(IndexKind, u32), RoaringBitmap> = index
            .into_iter()
            .map(|((k, key), bm)| if k == IndexKind::NameToken { ((k, remap[key as usize]), bm) } else { ((k, key), bm) })
            .collect();

        lap("assemble");
        if !progress(BuildPhase::Write, 0, 1) {
            return Err(MobileError::Cancelled);
        }
        let f = File::create(path)?;
        let mut w = BufWriter::with_capacity(1 << 20, f);
        w.write_all(MAGIC)?;
        w.write_all(&1u32.to_le_bytes())?;
        w.write_all(&count.to_le_bytes())?;
        w.write_all(&(dict.len() as u32).to_le_bytes())?;
        for s in &dict {
            write_str(&mut w, s)?;
        }
        w.write_all(&(order_r.len() as u32).to_le_bytes())?;
        for (fi, &ri) in order_r.iter().enumerate() {
            w.write_all(&regions[ri].0.to_le_bytes())?;
            w.write_all(&starts[fi].to_le_bytes())?;
            w.write_all(&regions[ri].1.to_le_bytes())?;
        }
        for &src in &perm {
            let mut r = records[src as usize];
            r[23] = final_ix[r[23] as usize];
            w.write_all(&r)?;
        }
        w.write_all(&(names.len() as u32).to_le_bytes())?;
        w.write_all(&names)?;
        w.write_all(&(index.len() as u32).to_le_bytes())?;
        let mut buf = Vec::new();
        for ((k, key), bm) in &index {
            buf.clear();
            bm.serialize_into(&mut buf)?;
            w.write_all(&[*k as u8])?;
            w.write_all(&key.to_le_bytes())?;
            w.write_all(&(buf.len() as u32).to_le_bytes())?;
            w.write_all(&buf)?;
        }
        w.write_all(&(order.len() as u32).to_le_bytes())?;
        for &o in &order {
            write_str(&mut w, &tokens[o as usize])?;
        }
        w.flush()?;
        lap("io");
        progress(BuildPhase::Write, 1, 1);
        Ok(count)
    }
}

fn write_str(w: &mut impl Write, s: &str) -> std::io::Result<()> {
    let b = s.as_bytes();
    let n = b.len().min(u16::MAX as usize);
    w.write_all(&(n as u16).to_le_bytes())?;
    w.write_all(&b[..n])
}

/// 名称切词：按空白与常见分隔符切，小写；去掉纯数字序号与倍率记号。
/// 递增写入的位图累加器：攒一批再 append（roaring 逐个 push ≈150 ns，批量 append 快 15 倍以上）。
#[derive(Default)]
struct BmAcc {
    bm: RoaringBitmap,
    buf: Vec<u32>,
}
impl BmAcc {
    #[inline]
    fn push(&mut self, i: u32) {
        self.buf.push(i);
        if self.buf.len() >= 4096 {
            self.flush();
        }
    }
    fn flush(&mut self) {
        if !self.buf.is_empty() {
            let _ = self.bm.append(self.buf.drain(..));
        }
    }
    fn finish(mut self) -> RoaringBitmap {
        self.flush();
        self.bm
    }
}

fn is_token_sep(c: char) -> bool {
    c.is_whitespace() || "|-_/·,()[]【】".contains(c)
}

fn normalize_token(raw: &str) -> Option<String> {
    let t = raw.trim();
    if t.is_empty() || t.starts_with('×') || t.chars().all(|c| c.is_ascii_digit()) {
        return None;
    }
    Some(t.to_lowercase())
}

pub fn name_tokens(name: &str) -> Vec<String> {
    let mut out: Vec<String> = name.split(is_token_sep).filter_map(normalize_token).collect();
    out.sort();
    out.dedup();
    out
}

struct Cursor<'a> {
    b: &'a [u8],
    p: usize,
}
impl<'a> Cursor<'a> {
    fn need(&self, n: usize) -> Result<(), MobileError> {
        if self.p + n > self.b.len() {
            Err(MobileError::Corrupt("节点文件截断".into()))
        } else {
            Ok(())
        }
    }
    fn u8(&mut self) -> Result<u8, MobileError> {
        self.need(1)?;
        self.p += 1;
        Ok(self.b[self.p - 1])
    }
    fn u16(&mut self) -> Result<u16, MobileError> {
        self.need(2)?;
        let v = u16::from_le_bytes([self.b[self.p], self.b[self.p + 1]]);
        self.p += 2;
        Ok(v)
    }
    fn u32(&mut self) -> Result<u32, MobileError> {
        self.need(4)?;
        let v = u32::from_le_bytes(self.b[self.p..self.p + 4].try_into().unwrap());
        self.p += 4;
        Ok(v)
    }
    fn bytes(&mut self, n: usize) -> Result<&'a [u8], MobileError> {
        self.need(n)?;
        let s = &self.b[self.p..self.p + n];
        self.p += n;
        Ok(s)
    }
    fn string(&mut self) -> Result<String, MobileError> {
        let n = self.u16()? as usize;
        Ok(String::from_utf8_lossy(self.bytes(n)?).into_owned())
    }
}

struct Region {
    code: String,
    start: u32,
    len: u32,
}

/// 只读 mmap 节点库。
pub struct NodeStore {
    map: Mmap,
    count: u32,
    dict: Vec<String>,
    dict_lc: Vec<String>,
    regions: Vec<Region>,
    records_off: usize,
    names_off: usize,
    /// (kind,key) → 位图在文件中的 (offset,len)，按需反序列化
    index: HashMap<(IndexKind, u32), (usize, usize)>,
    tokens: Vec<String>,
}

impl NodeStore {
    pub fn open(path: &Path) -> Result<Self, MobileError> {
        let f = File::open(path)?;
        // SAFETY: 文件由本库写出后只读打开；外部改写属于未定义使用，与 SQLite 等 mmap 实现同一假设。
        let map = unsafe { Mmap::map(&f)? };
        #[cfg(unix)]
        {
            let _ = map.advise(memmap2::Advice::Random);
        }
        let mut c = Cursor { b: &map, p: 0 };
        if c.bytes(8)? != MAGIC {
            return Err(MobileError::Corrupt("不是节点库文件".into()));
        }
        let _ver = c.u32()?;
        let count = c.u32()?;
        let nd = c.u32()? as usize;
        let mut dict = Vec::with_capacity(nd);
        for _ in 0..nd {
            dict.push(c.string()?);
        }
        let nr = c.u32()? as usize;
        let mut regions = Vec::with_capacity(nr);
        for _ in 0..nr {
            let d = c.u32()? as usize;
            let start = c.u32()?;
            let len = c.u32()?;
            regions.push(Region { code: dict.get(d).cloned().unwrap_or_default(), start, len });
        }
        let records_off = c.p;
        c.bytes(count as usize * RECORD_SIZE)?;
        let nl = c.u32()? as usize;
        let names_off = c.p;
        c.bytes(nl)?;
        let ni = c.u32()? as usize;
        let mut index = HashMap::with_capacity(ni);
        for _ in 0..ni {
            let k = c.u8()?;
            let key = c.u32()?;
            let l = c.u32()? as usize;
            let off = c.p;
            c.bytes(l)?;
            let kind = match k {
                0 => IndexKind::Region,
                1 => IndexKind::City,
                2 => IndexKind::Carrier,
                3 => IndexKind::Tag,
                4 => IndexKind::Protocol,
                5 => IndexKind::NameToken,
                _ => return Err(MobileError::Corrupt("未知索引类型".into())),
            };
            index.insert((kind, key), (off, l));
        }
        let nt = c.u32()? as usize;
        let mut tokens = Vec::with_capacity(nt);
        for _ in 0..nt {
            tokens.push(c.string()?);
        }
        let dict_lc = dict.iter().map(|s| s.to_lowercase()).collect();
        drop(c);
        Ok(Self { map, count, dict, dict_lc, regions, records_off, names_off, index, tokens })
    }

    pub fn total(&self) -> u64 {
        self.count as u64
    }

    fn bitmap(&self, kind: IndexKind, key: u32) -> Option<RoaringBitmap> {
        let &(off, len) = self.index.get(&(kind, key))?;
        RoaringBitmap::deserialize_unchecked_from(&self.map[off..off + len]).ok()
    }

    fn rec(&self, i: u32) -> &[u8] {
        let o = self.records_off + i as usize * RECORD_SIZE;
        &self.map[o..o + RECORD_SIZE]
    }

    pub fn row(&self, i: u32) -> NodeRow {
        let r = self.rec(i);
        let fp = u64::from_le_bytes(r[0..8].try_into().unwrap());
        let name_off = u32::from_le_bytes(r[8..12].try_into().unwrap()) as usize;
        let name_len = u16::from_le_bytes([r[12], r[13]]) as usize;
        let sub = u16::from_le_bytes([r[14], r[15]]);
        let city = u16::from_le_bytes([r[16], r[17]]);
        let carrier = u16::from_le_bytes([r[18], r[19]]);
        let (tag, proto, mult, rix) = (r[20], r[21], r[22], r[23]);
        let s = self.names_off + name_off;
        let d = |x: u32| self.dict.get(x as usize).cloned();
        NodeRow {
            id: fp,
            name: String::from_utf8_lossy(&self.map[s..s + name_len]).into_owned(),
            region: self.regions.get(rix as usize).map(|r| r.code.clone()).unwrap_or_default(),
            city: if city == u16::MAX { None } else { d(city as u32) },
            carrier: if carrier == u16::MAX { None } else { d(carrier as u32) },
            tag: if tag == u8::MAX { None } else { d(tag as u32) },
            protocol: d(proto as u32).unwrap_or_default(),
            multiplier: if mult == 0 { None } else { Some(mult as f32 / 10.0) },
            subscription: sub,
        }
    }

    /// 按 id（指纹）找行号：只在给定位图（通常是一页）里找，避免全表扫描。全库查找走 `find_in`。
    pub fn find_in(&self, id: u64, within: &RoaringBitmap) -> Option<u32> {
        within.iter().find(|&i| u64::from_le_bytes(self.rec(i)[0..8].try_into().unwrap()) == id)
    }

    /// 顺序扫描全部记录，返回 wanted 中存在的 (指纹, 行号)。只在测速节点首次排序时发生（1310 万行 × 24 B 顺序读，耗时待真机测）。
    pub fn scan_fingerprints(&self, wanted: &rustc_hash::FxHashSet<u64>) -> Vec<(u64, u32)> {
        let mut out = Vec::new();
        for i in 0..self.count {
            let fp = u64::from_le_bytes(self.rec(i)[0..8].try_into().unwrap());
            if wanted.contains(&fp) {
                out.push((fp, i));
                if out.len() == wanted.len() {
                    break;
                }
            }
        }
        out
    }

    pub fn fingerprints_sorted(&self) -> Vec<u64> {
        let mut v: Vec<u64> = (0..self.count).map(|i| u64::from_le_bytes(self.rec(i)[0..8].try_into().unwrap())).collect();
        v.sort_unstable();
        v
    }

    fn dict_matches(&self, kind: IndexKind, tok: &str, exact_or_contains: bool) -> Vec<u32> {
        // 在出现于该类索引的字典项里找
        self.index
            .keys()
            .filter(|(k, _)| *k == kind)
            .map(|(_, key)| *key)
            .filter(|&key| {
                let s = &self.dict_lc[key as usize];
                if exact_or_contains {
                    s == tok || s.contains(tok) || (tok.chars().count() >= 2 && tok.contains(s.as_str()))
                } else {
                    s == tok || s.replace(' ', "") == tok || s.split_whitespace().any(|w| w == tok) || (tok.chars().count() >= 2 && s.starts_with(tok))
                }
            })
            .collect()
    }

    fn region_name_matches(&self, tok: &str) -> Vec<u32> {
        // 代码全等，或中文名包含（中文名来自 region_names）
        self.regions
            .iter()
            .enumerate()
            .filter(|(_, r)| {
                let code = r.code.to_lowercase();
                code == tok || crate::regions::name_of(&r.code).map(|n| n.contains(tok) || tok.contains(n)).unwrap_or(false)
            })
            .map(|(i, _)| i as u32)
            .collect()
    }

    fn union(&self, kind: IndexKind, keys: &[u32]) -> RoaringBitmap {
        let mut acc = RoaringBitmap::new();
        for &k in keys {
            if let Some(b) = self.bitmap(kind, k) {
                acc |= b;
            }
        }
        acc
    }

    /// 查询：逐词匹配（地区 → 城市 → 运营商 → 标签/协议 → 名称词元前缀），各词位图取交集。
    /// 最后一个词若是 1–3 个 ASCII 字符且无匹配，视为正在输入而忽略（与原型一致）。
    pub fn query(&self, q: &str) -> (RoaringBitmap, Vec<String>, bool) {
        let toks: Vec<String> = q.split_whitespace().map(|t| t.to_lowercase()).collect();
        let mut acc: Option<RoaringBitmap> = None;
        let mut hl = Vec::new();
        let n = toks.len();
        for (ti, tk) in toks.iter().enumerate() {
            let last = ti + 1 == n;
            let mut bm: Option<RoaringBitmap> = None;
            let regs = self.region_name_matches(tk);
            if !regs.is_empty() {
                let mut b = RoaringBitmap::new();
                for r in regs {
                    let reg = &self.regions[r as usize];
                    b.insert_range(reg.start..reg.start + reg.len);
                }
                bm = Some(b);
                hl.push(tk.clone());
            }
            if bm.is_none() {
                for (kind, loose) in [(IndexKind::City, true), (IndexKind::Carrier, false), (IndexKind::Tag, false), (IndexKind::Protocol, false)] {
                    let keys = self.dict_matches(kind, tk, loose);
                    if !keys.is_empty() {
                        for &k in &keys {
                            hl.push(self.dict[k as usize].clone());
                        }
                        bm = Some(self.union(kind, &keys));
                        break;
                    }
                }
            }
            if bm.is_none() {
                // 名称词元前缀
                let lo = self.tokens.partition_point(|t| t.as_str() < tk.as_str());
                let keys: Vec<u32> = (lo..self.tokens.len()).take_while(|&i| self.tokens[i].starts_with(tk.as_str())).take(256).map(|i| i as u32).collect();
                if !keys.is_empty() {
                    hl.push(tk.clone());
                    bm = Some(self.union(IndexKind::NameToken, &keys));
                }
            }
            match bm {
                Some(b) => acc = Some(match acc { Some(a) => a & b, None => b }),
                None => {
                    let typing = last && tk.len() <= 3 && tk.chars().all(|c| c.is_ascii_alphanumeric() || c == '+' || c == '-');
                    if !typing {
                        return (RoaringBitmap::new(), hl, false);
                    }
                }
            }
        }
        let all = acc.is_none();
        let bm = acc.unwrap_or_else(|| {
            let mut b = RoaringBitmap::new();
            b.insert_range(0..self.count);
            b
        });
        (bm, hl, all)
    }

    pub fn sections(&self, bm: &RoaringBitmap) -> Vec<RegionSection> {
        let mut out = Vec::new();
        let mut row = 0u64;
        for r in &self.regions {
            let c = bm.range_cardinality(r.start..r.start + r.len);
            if c > 0 {
                out.push(RegionSection { region: r.code.clone(), count: c, row_offset: row });
                row += 1 + c;
            }
        }
        out
    }

    /// 结果集第 offset 个节点起 limit 个（不含分区头）。O(limit · log n)。
    pub fn page(&self, bm: &RoaringBitmap, offset: u64, limit: u32) -> Vec<NodeRow> {
        let limit = limit.min(MAX_PAGE);
        let Ok(off) = u32::try_from(offset) else { return vec![] };
        (0..limit).map_while(|k| off.checked_add(k).and_then(|n| bm.select(n))).map(|i| self.row(i)).collect()
    }

    pub fn timed_query(&self, q: &str) -> (RoaringBitmap, NodeQueryResult) {
        let t0 = Instant::now();
        let (bm, highlights, _) = self.query(q);
        let sections = self.sections(&bm);
        let res = NodeQueryResult {
            query: q.to_string(),
            total: bm.len(),
            sections,
            highlights,
            took_micros: t0.elapsed().as_micros() as u64,
            token: 0,
        };
        (bm, res)
    }

    pub fn region_codes(&self) -> Vec<(String, u64)> {
        self.regions.iter().map(|r| (r.code.clone(), r.len as u64)).collect()
    }
}
