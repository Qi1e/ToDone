import { AppState } from '../model/Types';

export interface MatterOperation {
  id: string;
  fingerprint: string;
}

export interface MatterReceipt extends MatterOperation {
  result: string;
}

export interface MatterSnapshot {
  version: number;
  revision: number;
  state: AppState;
  receipts: MatterReceipt[];
}

// compareAndSwap 必须原子检查版本并写入整份状态与回执。
export interface MatterPersistence {
  read(): Promise<MatterSnapshot>;
  compareAndSwap(expectedRevision: number, next: MatterSnapshot): Promise<boolean>;
}
