declare namespace util {
  class TextDecoder {
    static create(encoding?: string, options?: { fatal?: boolean; ignoreBOM?: boolean }): TextDecoder;
    decodeToString(input: Uint8Array, options?: { stream?: boolean }): string;
  }
}
export { util };
