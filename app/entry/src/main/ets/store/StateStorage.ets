// 原始 JSON 格式与键名由 preferences 适配器保持兼容。
export interface StateStorage {
  read(): string;
  write(snapshot: string): Promise<void>;
}
