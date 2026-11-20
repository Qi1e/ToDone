import { Want } from '@kit.AbilityKit';
import { FormExtensionAbility, formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { MatterStore } from '../store/MatterStore';
import { createCardBindingData } from '../widget/CardData';
import { refreshKnownCards } from '../widget/CardRefresh';
import { matterErrorMessage } from '../domain/MatterSnapshot';

interface CardEventPayload {
  message?: string;
  operationId?: string;
}

interface CardEvent {
  action: string;
  matterId: string;
  value: number;
  operationId?: string;
}

export default class EntryFormAbility extends FormExtensionAbility {
  private store: MatterStore = MatterStore.getInstance();

  onAddForm(want: Want): formBindingData.FormBindingData {
    const formId = this.extractFormId(want);
    this.synchronize(formId);
    const initial = createCardBindingData(this.store, formId);
    initial.secondary = '正在读取事项';
    return formBindingData.createFormBindingData(initial);
  }

  onUpdateForm(formId: string): void {
    this.synchronize(formId);
  }

  onFormEvent(formId: string, message: string): void {
    this.synchronize(formId, this.extractCardEvent(message));
  }

  onAcquireFormState(want: Want): formInfo.FormState {
    return formInfo.FormState.READY;
  }

  onRemoveForm(formId: string): void {
    this.remove(formId);
  }

  private async remove(formId: string): Promise<void> {
    try {
      await this.store.init(this.context);
      await this.store.removeCardForm(formId);
    } catch (error) {
      console.error('ToDone 卡片移除尚未保存');
    }
  }

  private async synchronize(formId: string, event?: CardEvent): Promise<void> {
    try {
      await this.store.init(this.context);
      if (!this.store.cardFormIds().includes(formId)) await this.store.rememberCardForm(formId);
      if (event && event.matterId) {
        if (event.action === 'record') {
          await this.store.addEventRecord(event.matterId, undefined, event.operationId);
        } else if (event.action === 'counter') {
          await this.store.addCounterEntry(event.matterId, event.value, event.operationId);
        }
      }
    } catch (error) {
      const data = createCardBindingData(this.store, formId);
      data.saveError = matterErrorMessage(error as Error);
      await formProvider.updateForm(formId, formBindingData.createFormBindingData(data)).catch(() => {
        console.error('ToDone 卡片错误提示更新失败');
      });
      return;
    }
    await formProvider.updateForm(formId, formBindingData.createFormBindingData(createCardBindingData(this.store, formId)))
      .catch(() => { console.error('ToDone 数据已保存，当前卡片刷新待重试'); });
    refreshKnownCards(this.store);
  }

  private extractFormId(want: Want): string {
    const params = want.parameters;
    if (!params) {
      return '';
    }
    const value = params[formInfo.FormParam.IDENTITY_KEY];
    if (value === undefined || value === null) {
      return '';
    }
    return `${value}`;
  }

  private extractCardEvent(message: string): CardEvent | undefined {
    let normalized = message;
    let operationId: string | undefined = undefined;
    try {
      const payload = JSON.parse(message) as CardEventPayload;
      operationId = payload.operationId;
      if (payload.message) {
        normalized = payload.message;
      }
    } catch (error) {
    }

    if (normalized.startsWith('record:')) {
      return {
        action: 'record',
        matterId: normalized.substring('record:'.length),
        value: 0,
        operationId
      };
    }
    if (normalized.startsWith('counter:')) {
      const parts = normalized.split(':');
      const parsedValue = parts.length > 2 ? Number(parts[2]) : 1;
      return {
        action: 'counter',
        matterId: parts.length > 1 ? parts[1] : '',
        value: parsedValue,
        operationId
      };
    }
    return undefined;
  }
}
