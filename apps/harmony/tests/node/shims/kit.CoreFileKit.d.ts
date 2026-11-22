declare namespace fileIo {
  interface File { readonly fd: number; readonly path: string; readonly name: string; }
  namespace OpenMode { const READ_ONLY: number; const WRITE_ONLY: number; const READ_WRITE: number; const CREATE: number; const TRUNC: number; const APPEND: number; }
  function accessSync(path: string): boolean;
  function mkdirSync(path: string, recursion?: boolean): void;
  function openSync(path: string, mode?: number): File;
  function writeSync(fd: number, buffer: ArrayBuffer | string): number;
  function fsyncSync(fd: number): void;
  function closeSync(file: number | File): void;
  function renameSync(oldPath: string, newPath: string): void;
  function readTextSync(filePath: string): string;
  function unlinkSync(path: string): void;
  interface Stat { readonly size: number; }
  function open(path: string, mode?: number): Promise<File>;
  function stat(file: string | number): Promise<Stat>;
  function read(fd: number, buffer: ArrayBuffer, options?: { offset?: number; length?: number }): Promise<number>;
  function close(file: number | File): Promise<void>;
}
declare namespace picker {
  class DocumentSelectOptions { maxSelectNumber?: number; fileSuffixFilters?: string[]; }
  class DocumentViewPicker { constructor(context?: object); select(option?: DocumentSelectOptions): Promise<string[]>; }
}
export { fileIo, picker };
