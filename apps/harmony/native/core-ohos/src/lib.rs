//! core-ohos：core-mobile 的 napi-ohos 薄层（M0，只导出少量 API 验证链路）。
//!
//! ArkTS 侧：`import core from 'libcore_ohos.so'`，类型见 `index.d.ts`。
//! 不做业务逻辑；新增导出时保持"一对一转发 + 类型转换"。

use std::sync::Arc;

use napi_derive_ohos::napi;
use napi_ohos::{Error, Result, Status};
use zephyr_mobile_core::{engine::core_greeting, MobileCore as Core, MobileError};

fn to_napi(e: MobileError) -> Error {
    Error::new(Status::GenericFailure, e.to_string())
}

/// core-ohos 自身版本（Cargo 包版本）。
#[napi]
pub fn version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

/// zephyr-core 链接探针（转发 core-mobile 的 `core_greeting`）。
#[napi]
pub fn greeting() -> String {
    core_greeting()
}

#[napi(object)]
pub struct SubscriptionsSummary {
    pub count: i32,
    pub total_nodes: i64,
}

#[napi(object)]
pub struct BuildReport {
    pub total: i64,
    pub skipped: i64,
    pub added: i64,
    pub removed: i64,
    pub kept: i64,
    pub took_millis: i64,
}

/// 包装 core-mobile 的 `MobileCore`。
/// §15.c 节点漏斗（`nodeFunnel` / §19.a `sceneFunnel` 共用）。
#[napi(object)]
pub struct NodeFunnel {
    pub source_count: u32,
    pub pool_size: i64,
    pub tested: i64,
    pub reachable: i64,
    pub under_threshold: i64,
    pub threshold_ms: i32,
}

impl From<zephyr_mobile_core::node_api::NodeFunnel> for NodeFunnel {
    fn from(f: zephyr_mobile_core::node_api::NodeFunnel) -> Self {
        Self {
            source_count: f.source_count,
            pool_size: f.pool_size as i64,
            tested: f.tested as i64,
            reachable: f.reachable as i64,
            under_threshold: f.under_threshold as i64,
            threshold_ms: f.threshold_ms,
        }
    }
}

#[napi(js_name = "MobileCore")]
pub struct JsMobileCore {
    inner: Arc<Core>,
}

#[napi]
impl JsMobileCore {
    /// data_dir：应用沙箱 filesDir 下的目录。
    #[napi(constructor)]
    pub fn new(data_dir: String) -> Result<Self> {
        Ok(Self { inner: Core::new(data_dir).map_err(to_napi)? })
    }

    /// 同步：订阅数与节点总数。
    #[napi]
    pub fn subscriptions_summary(&self) -> SubscriptionsSummary {
        let s = self.inner.subscriptions_summary();
        SubscriptionsSummary { count: s.count, total_nodes: s.total_nodes }
    }

    /// 异步（tokio 阻塞线程池，不占 ArkTS 主线程）：用 mock 生成器建库，scale=1.0 约 1300 万节点。
    #[napi]
    pub async fn rebuild_mock_nodes(&self, scale: f64) -> Result<BuildReport> {
        let core = self.inner.clone();
        let r = napi_ohos::tokio::task::spawn_blocking(move || core.rebuild_mock_nodes(scale))
            .await
            .map_err(|e| Error::new(Status::GenericFailure, format!("join: {e}")))?
            .map_err(to_napi)?;
        Ok(BuildReport {
            total: r.total as i64,
            skipped: r.skipped as i64,
            added: r.diff.added as i64,
            removed: r.diff.removed as i64,
            kept: r.diff.kept as i64,
            took_millis: r.took_millis as i64,
        })
    }

    /// 同步：§15.c 全局节点漏斗（场景 sheet lede、§18.a 节点页判断句）。
    #[napi]
    pub fn node_funnel(&self, now_millis: i64, max_age_millis: i64, threshold_ms: i32) -> Result<NodeFunnel> {
        self.inner.node_funnel(now_millis, max_age_millis, threshold_ms).map(NodeFunnel::from).map_err(to_napi)
    }

    /// 同步：§19.a 场景漏斗（首页场景卡迷你漏斗）；未知 sceneId 抛错（SceneNotFound）。
    #[napi]
    pub fn scene_funnel(&self, scene_id: String, now_millis: i64, max_age_millis: i64, threshold_ms: i32) -> Result<NodeFunnel> {
        self.inner.scene_funnel(scene_id, now_millis, max_age_millis, threshold_ms).map(NodeFunnel::from).map_err(to_napi)
    }
}
