import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { StateStorage } from './StateStorage';

export class PreferencesStateStorage implements StateStorage {
  private pref: preferences.Preferences;
  private key: string;

  constructor(context: common.UIAbilityContext | common.FormExtensionContext,
    name: string = 'todone_store', key: string = 'app_state_v1') {
    this.pref = preferences.getPreferencesSync(context, { name: name });
    this.key = key;
  }

  read(): string {
    return this.pref.getSync(this.key, '') as string;
  }

  write(snapshot: string): Promise<void> {
    this.pref.putSync(this.key, snapshot);
    return this.pref.flush();
  }
}
