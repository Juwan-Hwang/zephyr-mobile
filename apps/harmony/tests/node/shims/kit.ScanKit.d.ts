declare namespace scanCore {
  enum ScanType { QR_CODE = 11 }
  enum ScanErrorCode { INTERNAL_ERROR = 1000500001, SCAN_SERVICE_CANCELED = 1000500002 }
}
declare namespace scanBarcode {
  interface ScanOptions { scanTypes?: scanCore.ScanType[]; enableMultiMode?: boolean; enableAlbum?: boolean; }
  interface ScanResult { scanType: scanCore.ScanType; originalValue: string; }
  function startScanForResult(context: object, options?: ScanOptions): Promise<ScanResult>;
}
export { scanCore, scanBarcode };
