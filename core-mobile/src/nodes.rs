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
    let mut buf = Vec::with_capacity(server.len() + protocol.len() + 8);
    buf.extend(server.trim().to_ascii_lowercase().as_bytes());
    buf.push(0);
    buf.extend(port.to_le_bytes());
    buf.push(0);
    buf.extend(protocol.trim().to_ascii_lowercase().as_bytes());
    xxhash_rust::xxh3::xxh3_64(&buf)
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

pub struct NodeStoreBuilder {
    nodes: Vec<NodeInput>,
}

impl Default for NodeStoreBuilder {
    fn default() -> Self {
        Self::new()
    }
}

impl NodeStoreBuilder {
    pub fn new() -> Self {
        Self { nodes: Vec::new() }
    }
    pub fn with_capacity(n: usize) -> Self {
        Self { nodes: Vec::with_capacity(n) }
    }
    pub fn push(&mut self, n: NodeInput) {
        self.nodes.push(n);
    }
    pub fn len(&self) -> usize {
        self.nodes.len()
    }
    pub fn is_empty(&self) -> bool {
        self.nodes.is_empty()
    }

    /// 写出到文件。同指纹去重（保留先出现的）。地区按节点数降序排列（与原型一致：大地区在前）。
    pub fn write(mut self, path: &Path) -> Result<u32, MobileError> {
        // 去重
        let mut seen = std::collections::HashSet::with_capacity(self.nodes.len());
        self.nodes.retain(|n| seen.insert(fingerprint(&n.server, n.port, &n.protocol)));
        // 地区排序
        let mut region_count: HashMap<String, u32> = HashMap::new();
        for n in &self.nodes {
            *region_count.entry(n.region.clone()).or_default() += 1;
        }
        let mut regions: Vec<(String, u32)> = region_count.into_iter().collect();
        regions.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(&b.0)));
        if regions.len() > 255 {
            return Err(MobileError::Invalid("超过 255 个地区".into()));
        }
        let region_ix: HashMap<String, u8> = regions.iter().enumerate().map(|(i, (r, _))| (r.clone(), i as u8)).collect();
        // 稳定排序：地区内保持输入顺序
        self.nodes.sort_by_key(|n| region_ix[&n.region]);

        // 字典
        let mut dict: Vec<String> = Vec::new();
        let mut dict_ix: HashMap<String, u32> = HashMap::new();
        let mut intern = |s: &str, dict: &mut Vec<String>| -> u32 {
            if let Some(&i) = dict_ix.get(s) {
                return i;
            }
            let i = dict.len() as u32;
            dict.push(s.to_string());
            dict_ix.insert(s.to_string(), i);
            i
        };
        let region_dict: Vec<u32> = regions.iter().map(|(r, _)| intern(r, &mut dict)).collect();

        let mut index: BTreeMap<(IndexKind, u32), RoaringBitmap> = BTreeMap::new();
        let mut tokens: Vec<String> = Vec::new();
        let mut token_ix: HashMap<String, u32> = HashMap::new();
        let mut records = Vec::with_capacity(self.nodes.len() * RECORD_SIZE);
        let mut names: Vec<u8> = Vec::new();
        let mut starts = vec![0u32; regions.len()];
        let mut lens = vec![0u32; regions.len()];
        let mut first = vec![true; regions.len()];

        for (i, n) in self.nodes.iter().enumerate() {
            let i = i as u32;
            let rix = region_ix[&n.region] as usize;
            if first[rix] {
                starts[rix] = i;
                first[rix] = false;
            }
            lens[rix] += 1;
            let opt16 = |o: &Option<String>, dict: &mut Vec<String>, intern: &mut dyn FnMut(&str, &mut Vec<String>) -> u32| -> u16 {
                match o {
                    Some(s) if !s.is_empty() => intern(s, dict) as u16,
                    _ => u16::MAX,
                }
            };
            let city = opt16(&n.city, &mut dict, &mut intern);
            let carrier = opt16(&n.carrier, &mut dict, &mut intern);
            let tag = match &n.tag {
                Some(s) if !s.is_empty() => intern(s, &mut dict) as u8,
                _ => u8::MAX,
            };
            let proto = intern(&n.protocol, &mut dict) as u8;
            if dict.len() > u16::MAX as usize - 1 {
                return Err(MobileError::Invalid("属性字典过大".into()));
            }
            let fp = fingerprint(&n.server, n.port, &n.protocol);
            let name_off = names.len() as u32;
            let nb = n.name.as_bytes();
            let name_len = nb.len().min(u16::MAX as usize) as u16;
            names.extend_from_slice(&nb[..name_len as usize]);

            records.extend(fp.to_le_bytes());
            records.extend(name_off.to_le_bytes());
            records.extend(name_len.to_le_bytes());
            records.extend(n.subscription.to_le_bytes());
            records.extend(city.to_le_bytes());
            records.extend(carrier.to_le_bytes());
            records.push(tag);
            records.push(proto);
            records.push(n.multiplier_x10);
            records.push(rix as u8);

            index.entry((IndexKind::Region, region_dict[rix])).or_default().insert(i);
            if city != u16::MAX {
                index.entry((IndexKind::City, city as u32)).or_default().insert(i);
            }
            if carrier != u16::MAX {
                index.entry((IndexKind::Carrier, carrier as u32)).or_default().insert(i);
            }
            if tag != u8::MAX {
                index.entry((IndexKind::Tag, tag as u32)).or_default().insert(i);
            }
            index.entry((IndexKind::Protocol, proto as u32)).or_default().insert(i);
            for t in name_tokens(&n.name) {
                let id = *token_ix.entry(t.clone()).or_insert_with(|| {
                    tokens.push(t.clone());
                    (tokens.len() - 1) as u32
                });
                index.entry((IndexKind::NameToken, id)).or_default().insert(i);
            }
        }

        // 词元字典排序（前缀查找），并重映射 id
        let mut order: Vec<u32> = (0..tokens.len() as u32).collect();
        order.sort_by(|&a, &b| tokens[a as usize].cmp(&tokens[b as usize]));
        let mut remap = vec![0u32; tokens.len()];
        for (new, &old) in order.iter().enumerate() {
            remap[old as usize] = new as u32;
        }
        let sorted_tokens: Vec<&String> = order.iter().map(|&o| &tokens[o as usize]).collect();
        let index: BTreeMap<(IndexKind, u32), RoaringBitmap> = index
            .into_iter()
            .map(|((k, key), bm)| if k == IndexKind::NameToken { ((k, remap[key as usize]), bm) } else { ((k, key), bm) })
            .collect();

        let f = File::create(path)?;
        let mut w = BufWriter::with_capacity(1 << 20, f);
        let count = self.nodes.len() as u32;
        w.write_all(MAGIC)?;
        w.write_all(&1u32.to_le_bytes())?;
        w.write_all(&count.to_le_bytes())?;
        w.write_all(&(dict.len() as u32).to_le_bytes())?;
        for s in &dict {
            write_str(&mut w, s)?;
        }
        w.write_all(&(regions.len() as u32).to_le_bytes())?;
        for (i, d) in region_dict.iter().enumerate() {
            w.write_all(&d.to_le_bytes())?;
            w.write_all(&starts[i].to_le_bytes())?;
            w.write_all(&lens[i].to_le_bytes())?;
        }
        w.write_all(&records)?;
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
        w.write_all(&(sorted_tokens.len() as u32).to_le_bytes())?;
        for t in sorted_tokens {
            write_str(&mut w, t)?;
        }
        w.flush()?;
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
pub fn name_tokens(name: &str) -> Vec<String> {
    let mut out: Vec<String> = name
        .split(|c: char| c.is_whitespace() || "|-_/·,()[]【】".contains(c))
        .map(|t| t.trim().to_lowercase())
        .filter(|t| !t.is_empty() && !t.starts_with('×') && !t.chars().all(|c| c.is_ascii_digit()))
        .collect();
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
