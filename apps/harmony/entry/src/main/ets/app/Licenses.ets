/*
 * 开源许可（M1-17；对照 Android LicensesScreen）：三份文件由构建放进 rawfile/licenses/
 * （tools/build-hmos.sh 与 entry/hvigorfile.ts 从仓库根复制，不入库）：
 * LICENSE（本 App）、THIRD_PARTY_NOTICES.md、THIRD_PARTY_LICENSES.txt（约 700 KB）。
 * 按空行切块，交给 LazyForEach 懒渲染；块再用 "\n\n" 拼回即原文（连续空行折成一行）。
 */
export const SOURCE_URL: string = 'https://github.com/Juwan-Hwang/zephyr-mobile';

export enum LicenseDoc {
  APP = 'LICENSE',
  NOTICES = 'THIRD_PARTY_NOTICES.md',
  TEXTS = 'THIRD_PARTY_LICENSES.txt'
}

export const LICENSE_DOCS: LicenseDoc[] = [LicenseDoc.APP, LicenseDoc.NOTICES, LicenseDoc.TEXTS];

export interface LicenseRow {
  key: string;
  /** true = 分组标题行（text 为空，doc 决定标题）。 */
  header: boolean;
  doc: LicenseDoc;
  text: string;
}

export class Licenses {
  static rawPath(doc: LicenseDoc): string {
    return 'licenses/' + doc;
  }

  /** 每个版本的源码是 mobile-v<version> tag（docs/release.md D1）。 */
  static sourceTag(versionName: string): string {
    return 'mobile-v' + versionName;
  }

  static blocks(text: string): string[] {
    return text.replace(new RegExp('\r\n', 'g'), '\n').split(new RegExp('\n[ \t]*\n+'))
      .map((b: string) => b.replace(new RegExp('\\s+$'), ''))
      .filter((b: string) => b.trim().length > 0);
  }

  /** 拼行：每份非空文件一个标题行 + 它的块；全空时返回空数组（页面显示“无法加载”）。 */
  static rows(texts: Map<LicenseDoc, string>): LicenseRow[] {
    const out: LicenseRow[] = [];
    for (const doc of LICENSE_DOCS) {
      const t = texts.get(doc);
      const blocks = t !== undefined ? Licenses.blocks(t) : [];
      if (blocks.length === 0) {
        continue;
      }
      out.push({ key: 'h-' + doc, header: true, doc: doc, text: '' });
      blocks.forEach((b: string, i: number) => {
        out.push({ key: doc + '-' + i, header: false, doc: doc, text: b });
      });
    }
    return out;
  }
}

export class LicenseRowSource implements IDataSource {
  private rows: LicenseRow[] = [];
  private listeners: DataChangeListener[] = [];

  set(rows: LicenseRow[]): void {
    this.rows = rows;
    for (const l of this.listeners) {
      l.onDataReloaded();
    }
  }

  totalCount(): number {
    return this.rows.length;
  }

  getData(index: number): LicenseRow {
    return this.rows[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const i = this.listeners.indexOf(listener);
    if (i >= 0) {
      this.listeners.splice(i, 1);
    }
  }
}
