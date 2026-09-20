import { Want } from '@kit.AbilityKit';
import { FormExtensionAbility, formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { MatterStore } from '../store/MatterStore';
import { createCardBindingData } from '../widget/CardData';

interface CardEventPayload {
  message?: string;
}

interface CardEvent {
  action: string;
  matterId: string;
  value: number;
}

export default class EntryFormAbility extends FormExtensionAbility {
  private store: MatterStore = MatterStore.getInstance();

  onAddForm(want: Want): formBindingData.FormBindingData {
    this.ensureStore();
    const formId = this.extractFormId(want);
    this.store.rememberCardForm(formId);
    const data = this.createBindingData();
    if (formId.length > 0) {
      formProvider.updateForm(formId, data).then(() => {
      }).catch(() => {
      });
    }
    return data;
  }

  onUpdateForm(formId: string): void {
    this.ensureStore();
    this.store.rememberCardForm(formId);
    this.updateFormData(formId);
  }

  onFormEvent(formId: string, message: string): void {
    this.ensureStore();
    this.store.rememberCardForm(formId);
    const event = this.extractCardEvent(message);
    if (event && event.matterId.length > 0) {
      if (event.action === 'record') {
        this.store.addEventRecord(event.matterId);
      }
      if (event.action === 'counter') {
        this.store.addCounterEntry(event.matterId, event.value);
      }
    }
    this.updateFormData(formId);
  }

  onAcquireFormState(want: Want): formInfo.FormState {
    return formInfo.FormState.READY;
  }

  onRemoveForm(formId: string): void {
    this.ensureStore();
    this.store.removeCardForm(formId);
  }

  private ensureStore(): void {
    this.store.init(this.context);
  }

  private createBindingData(): formBindingData.FormBindingData {
    return formBindingData.createFormBindingData(createCardBindingData(this.store));
  }

  private updateFormData(formId: string): void {
    formProvider.updateForm(formId, this.createBindingData()).then(() => {
    }).catch(() => {
    });
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
    try {
      const payload = JSON.parse(message) as CardEventPayload;
      if (payload.message) {
        normalized = payload.message;
      }
    } catch (error) {
    }

    if (normalized.startsWith('record:')) {
      return {
        action: 'record',
        matterId: normalized.substring('record:'.length),
        value: 0
      };
    }
    if (normalized.startsWith('counter:')) {
      const parts = normalized.split(':');
      const parsedValue = parts.length > 2 ? Number(parts[2]) : 1;
      return {
        action: 'counter',
        matterId: parts.length > 1 ? parts[1] : '',
        value: Number.isNaN(parsedValue) ? 1 : parsedValue
      };
    }
    return undefined;
  }
}
