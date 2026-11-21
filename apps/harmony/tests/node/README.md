# apps/harmony node 侧测试

不需要 DevEco、HarmonyOS SDK 或设备，只要 node ≥ 22.7（`--experimental-transform-types`，ArkTS 用 `enum`）。

```sh
apps/harmony/tests/node/run.sh          # 全部
apps/harmony/tests/node/run.sh nodes    # 只跑文件名含 nodes 的测试
```

做三件事：

1. **tsc --noEmit**：把 `entry/src/main/ets` 下不含 `@Entry` / `@Component` 的 `.ets` 拷成 `.ts`，`@kit.*` 由 `shims/` 里手写的最小声明代替，strict 模式检查。页面组件（ArkUI 声明式语法）不在此列，靠 `tools/build-hmos.sh` 的真实编译。
2. **ArkTS 严格模式禁用项扫描**（`lint.sh`，engine/**）：any / unknown / 索引签名 / 解构 / 正则字面量 / 对象展开 / var / for-in。
3. **运行时测试**：`.out/rt` = 上面的拷贝 + `rtstub/` 里 `@kit` 的运行时替身（文件、VPN 等），
   - `cases/*.mjs`：契约 fixtures（`contract/fixtures/*.json`：mock-v0、import-payload、uhd-names、command-parse）、VPN 路由表、深链、吐司 / 撤销、指令规划与应用、最近连接；
   - `model/*.mjs`：页面背后的纯逻辑模型（节点列表、订阅、场景 sheet、轨迹、导航、Today、格式化……）。

新增纯逻辑（`app/*Model.ets` 等）时，在 `model/` 加一个同名 `.mjs`，从 `../.out/rt/…/X.ts` 动态 import，失败时 `process.exit(1)`。
设备上的界面测试在 `entry/src/ohosTest`（Hypium / UiTest）。
