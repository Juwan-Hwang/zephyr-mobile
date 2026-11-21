export namespace hilog {
  function info(domain: number, tag: string, format: string, ...args: Object[]): void;
  function warn(domain: number, tag: string, format: string, ...args: Object[]): void;
  function error(domain: number, tag: string, format: string, ...args: Object[]): void;
}
