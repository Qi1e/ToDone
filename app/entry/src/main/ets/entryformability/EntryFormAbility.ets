import { Want } from '@kit.AbilityKit';
import { FormExtensionAbility, formBindingData } from '@kit.FormKit';

export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    return formBindingData.createFormBindingData({
      title: 'ToDone',
      primary: '事项',
      secondary: '打开 App 管理模块'
    });
  }

  onUpdateForm(formId: string): void {
  }
}

