import { MatterRepository } from '../contracts/MatterService';
import { DefaultMatterService } from '../domain/DefaultMatterService';
import { createSeedState } from '../model/Defaults';
import { AppState } from '../model/Types';

export class MemoryMatterRepository implements MatterRepository {
  private state: AppState;

  constructor(state: AppState = createSeedState()) {
    this.state = JSON.parse(JSON.stringify(state)) as AppState;
  }

  readState(): AppState {
    return JSON.parse(JSON.stringify(this.state)) as AppState;
  }

  async commitState(state: AppState): Promise<void> {
    this.state = JSON.parse(JSON.stringify(state)) as AppState;
  }
}

// 与真实实现复用相同业务规则，仅替换数据仓库，不访问设备存储或卡片。
export class MockMatterService extends DefaultMatterService {
  constructor(state: AppState = createSeedState()) {
    super(new MemoryMatterRepository(state));
  }
}
