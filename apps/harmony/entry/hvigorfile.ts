import { hapTasks } from '@ohos/hvigor-ohos-plugin';
import * as fs from 'fs';
import * as path from 'path';

/**
 * 开源许可原文（仓库根的 LICENSE / THIRD_PARTY_NOTICES.md / THIRD_PARTY_LICENSES.txt）复制到
 * src/main/resources/rawfile/licenses/，同 Android bundleLicenseAssets。仓库根不在（如 tools/build-hmos.sh 的临时副本，
 * 那边由脚本自己复制）时什么也不做。
 */
function bundleLicenses() {
  return {
    pluginId: 'zephyrBundleLicenses',
    apply(node: { getNodePath(): string }): void {
      const moduleDir = node.getNodePath();
      const repo = path.resolve(moduleDir, '..', '..', '..');
      const out = path.join(moduleDir, 'src', 'main', 'resources', 'rawfile', 'licenses');
      for (const f of ['LICENSE', 'THIRD_PARTY_NOTICES.md', 'THIRD_PARTY_LICENSES.txt']) {
        const src = path.join(repo, f);
        if (fs.existsSync(src)) {
          fs.mkdirSync(out, { recursive: true });
          fs.copyFileSync(src, path.join(out, f));
        }
      }
    }
  };
}

export default {
  system: hapTasks, /* Built-in plugin of Hvigor. It cannot be modified. */
  plugins: [bundleLicenses()]
}
