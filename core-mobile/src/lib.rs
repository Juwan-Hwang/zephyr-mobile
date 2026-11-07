//! Zephyr 移动端核心扩展（只在 zephyr-mobile 内；桌面 zephyr-core 以只读子模块依赖）。
//!
//! 模块：
//! - `nodes`：千万级节点 mmap 存储、属性倒排（Roaring）、查询与分页
//! - `rules`：上亿规则编译（域名哈希排序表 / CIDR 压平区段 / 关键字 AC 自动机）与逐层测试
//! - `subscription`：Clash YAML → 节点；`regions`：地区识别；`diff`：订阅差异
//! - `engine`：UniFFI 对象 `MobileCore`
//! - `mock`：原型数据生成器移植（基准与一致性测试）

uniffi::setup_scaffolding!("zephyr_mobile_core");

pub mod diff;
pub mod engine;
pub mod error;
pub mod latency;
pub mod mihomo;
pub mod mock;
pub mod node_api;
pub mod nodes;
pub mod regions;
pub mod rules;
pub mod runtime_config;
pub mod failover;
pub mod scene_api;
pub mod scenes;
pub mod subs;
pub mod subscription;

pub use engine::MobileCore;
pub use error::MobileError;
