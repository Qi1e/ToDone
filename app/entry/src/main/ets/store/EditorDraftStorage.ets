import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

// Split long notes and lists below the per-value Preferences size limit.
export class EditorDraftStorage {
  private pref: preferences.Preferences;
  private key: string;

  constructor(context: common.UIAbilityContext, key: string) {
    this.pref = preferences.getPreferencesSync(context, { name: 'todone_editor_v1' });
    this.key = key;
  }

  read(): string {
    const count = this.pref.getSync(this.key, 0) as number;
    let text = '';
    for (let i = 0; i < count; i++) text += this.pref.getSync(this.key + '_' + i, '') as string;
    return text;
  }

  async write(text: string): Promise<void> {
    const previous = this.pref.getSync(this.key, 0) as number;
    let count = 0;
    let start = 0;
    while (start < text.length) {
      let end = Math.min(text.length, start + 1000);
      const last = text.charCodeAt(end - 1);
      if (end < text.length && last >= 0xd800 && last <= 0xdbff) end--;
      this.pref.putSync(this.key + '_' + count, text.slice(start, end));
      count++;
      start = end;
    }
    for (let i = count; i < previous; i++) this.pref.deleteSync(this.key + '_' + i);
    if (count) this.pref.putSync(this.key, count);
    else this.pref.deleteSync(this.key);
    await this.pref.flush();
  }
}
