/*
 * 服务卡片快照 / 卡片 id 的落盘（filesDir 下两个小 JSON）。UI 进程与卡片进程各自读写；每次都读文件，
 * 不用 preferences（其内存缓存跨进程不同步）。写入走临时文件 + rename，读到的一定是完整内容。
 */
import { fileIo } from '@kit.CoreFileKit';
import { CARD_FORMS_FILE, CARD_SNAPSHOT_FILE, CardSnapshot, CardSnapshots } from './CardSnapshot';

export class CardStore {
  static readText(path: string): string | undefined {
    try {
      if (!fileIo.accessSync(path)) {
        return undefined;
      }
      return fileIo.readTextSync(path);
    } catch (e) {
      return undefined;
    }
  }

  static writeText(path: string, text: string): void {
    const tmp = path + '.tmp';
    const f = fileIo.openSync(tmp, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(f.fd, text);
    } finally {
      fileIo.closeSync(f);
    }
    fileIo.renameSync(tmp, path);
  }

  static snapshot(filesDir: string): CardSnapshot {
    return CardSnapshots.decode(CardStore.readText(filesDir + '/' + CARD_SNAPSHOT_FILE));
  }

  static saveSnapshot(filesDir: string, s: CardSnapshot): void {
    CardStore.writeText(filesDir + '/' + CARD_SNAPSHOT_FILE, CardSnapshots.encode(s));
  }

  static ids(filesDir: string): string[] {
    return CardSnapshots.decodeIds(CardStore.readText(filesDir + '/' + CARD_FORMS_FILE));
  }

  static saveIds(filesDir: string, ids: string[]): void {
    CardStore.writeText(filesDir + '/' + CARD_FORMS_FILE, JSON.stringify(ids));
  }
}
