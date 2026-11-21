export namespace window {
  interface WindowStage { loadContent(path: string, callback: (err: BusinessErrorLike) => void): void; }
  interface BusinessErrorLike { code: number; message: string }
}
export class AppStorageV2 {
  static connect<T extends object>(type: new () => T, key: string, creator: () => T): T | undefined;
}
