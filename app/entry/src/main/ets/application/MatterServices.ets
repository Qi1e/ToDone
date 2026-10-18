import { common } from '@kit.AbilityKit';
import { MatterService } from '../contracts/MatterService';
import { DefaultMatterService } from '../domain/DefaultMatterService';
import { MatterStore } from '../store/MatterStore';
import { CardRefreshResult, refreshKnownCards } from '../widget/CardRefresh';

export class MatterServices {
  private static service: MatterService = new DefaultMatterService(MatterStore.getInstance());
  private static previewMode: boolean = false;

  static initialize(context: common.UIAbilityContext): void {
    if (!MatterServices.previewMode) MatterStore.getInstance().init(context);
  }

  static getService(): MatterService {
    return MatterServices.service;
  }

  // 仅用于本地预览；必须在页面创建前注入，提交时保持真实实现为默认值。
  static setForPreview(service: MatterService): void {
    MatterServices.service = service;
    MatterServices.previewMode = true;
  }

  static isPreview(): boolean {
    return MatterServices.previewMode;
  }

  static requestCardRefresh(): CardRefreshResult {
    if (MatterServices.previewMode) {
      return { requested: 0, message: '预览数据仅保存在内存中' };
    }
    try {
      return refreshKnownCards(MatterStore.getInstance());
    } catch (error) {
      return { requested: 0, message: '卡片刷新请求未完成，请稍后重试' };
    }
  }
}
