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
}
export { fileIo };
