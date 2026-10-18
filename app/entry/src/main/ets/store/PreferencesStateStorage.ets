import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { StateStorage } from './StateStorage';

export class PreferencesStateStorage implements StateStorage {
  private pref: preferences.Preferences;

  constructor(context: common.UIAbilityContext | common.FormExtensionContext) {
    this.pref = preferences.getPreferencesSync(context, { name: 'todone_store' });
  }

  read(): string {
    return this.pref.getSync('app_state_v1', '') as string;
  }

  write(snapshot: string): Promise<void> {
    this.pref.putSync('app_state_v1', snapshot);
    return this.pref.flush();
  }
}
