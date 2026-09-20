import { formBindingData, formProvider } from '@kit.FormKit';
import { MatterStore } from '../store/MatterStore';
import { createCardBindingData } from './CardData';

export interface CardRefreshResult {
  requested: number;
  message: string;
}

export function refreshKnownCards(store: MatterStore): CardRefreshResult {
  const formIds = store.cardFormIds();
  if (formIds.length === 0) {
    return {
      requested: 0,
      message: '设置已保存；添加或刷新桌面卡片后生效'
    };
  }

  const data = formBindingData.createFormBindingData(createCardBindingData(store));
  formIds.forEach((formId: string) => {
    formProvider.updateForm(formId, data).then(() => {
    }).catch(() => {
    });
  });

  return {
    requested: formIds.length,
    message: `已请求刷新 ${formIds.length} 张桌面卡片`
  };
}

