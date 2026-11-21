import fs from 'node:fs';
export const fileIo = {
  OpenMode: { READ_ONLY: 0, WRITE_ONLY: 1, READ_WRITE: 2, CREATE: 0o100, TRUNC: 0o1000, APPEND: 0o2000 },
  accessSync: (p: string) => fs.existsSync(p),
  mkdirSync: (p: string, r?: boolean) => fs.mkdirSync(p, { recursive: !!r }),
  openSync: (p: string, m: number) => ({ fd: fs.openSync(p, 'w'), path: p, name: p }),
  writeSync: (fd: number, s: string) => fs.writeSync(fd, s),
  fsyncSync: (fd: number) => fs.fsyncSync(fd),
  closeSync: (f: any) => fs.closeSync(typeof f === 'number' ? f : f.fd),
  renameSync: (a: string, b: string) => fs.renameSync(a, b),
  readTextSync: (p: string) => fs.readFileSync(p, 'utf8'),
  unlinkSync: (p: string) => fs.unlinkSync(p),
};
