// archiver 8.x 的最小类型声明（ESM 包，无自带类型；直接导出类，无工厂函数）
declare module 'archiver' {
  import { Transform } from 'stream';

  export class ZipArchive extends Transform {
    constructor(options?: { zlib?: { level?: number } });
    append(source: string | Buffer | NodeJS.ReadableStream, data: { name: string }): this;
    file(filePath: string, data: { name: string }): this;
    finalize(): Promise<void>;
  }
}
