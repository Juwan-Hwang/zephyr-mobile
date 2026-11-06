# Scale target: 10^7–10^8 nodes and rules on mobile (draft, 2026-11-06)

User requirement (08:39): support node and rule counts from tens of millions up to hundreds of millions.

## UI (prototype design/prototype pages.*, built by build.py)
- The node list is virtual: it renders only visible rows and uses its own scroll offset. A browser or native scroll height can't hold 10^8 rows, and native needs an equivalent such as LazyColumn with a fixed row height, or a UICollectionView with a custom scroller.
- The right-side region index rail jumps straight to a section, and the header stays pinned. The footer shows position "n / total" and the tested count.
- Search runs against indexes (region, city, line tag) and gives a count plus the first page. It never scans every row.
- Latency shows only cached values. Visible rows are tested after scrolling stops for 400 ms; nothing else is tested in bulk.
- The rules page shows 7 layers in match order with counts, plus a domain/IP test that shows the chain (layer → rule → scene → exit IP) and the time taken.

## Core (to verify in a spike)
- Nodes: columnar on-disk store (SQLite WITHOUT ROWID or a custom mmap file) keyed by a server+port+protocol fingerprint. Name search through an FST / trigram index. About 13M nodes × ~60 B ≈ 0.8 GB on disk; RAM holds only the page cache.
- Rules: rule-sets compiled into read-only succinct structures (domain suffix trie/FST, IP CIDR interval tree, like mihomo's MRS format) and mmap'd. Lookup is O(len(domain)). Keyword rules need Aho-Corasick.
- Risk: the iOS NetworkExtension memory cap (~50 MB, unverified). It's unclear whether clean file-backed mmap pages count against it. Must be measured on device with 10^8 rules before promising.
- Subscriptions: incremental diff on update (+/− nodes, rule changes); overrides (Prism) are kept.
- Bulk latency testing across millions of nodes is out of scope; testing is on demand and scene-pool only.
