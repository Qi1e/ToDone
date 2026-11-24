import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { TimelineReminders } from '../application/TimelineReminders';
import { MatterServices } from '../application/MatterServices';
import { timelineReadCode } from '../domain/TimelineReadError';
import { MatterStore } from '../store/MatterStore';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, 'ToDone', 'EntryAbility created');
  }

  onForeground(): void {
    this.reloadAndSyncReminders();
  }

  private async reloadAndSyncReminders(): Promise<void> {
    try {
      await MatterServices.initialize(this.context);
    } catch (error) {
      hilog.error(0x0000, 'ToDone', 'Matter reload failed on foreground');
      return;
    }
    try {
      const blocks = MatterStore.getInstance().reminderBlocks();
      const status = await TimelineReminders.sync(this.context, blocks);
      if (status) hilog.info(0x0000, 'ToDone', 'Timeline reminder sync: %{public}s', status);
    } catch (error) {
      hilog.warn(0x0000, 'ToDone', 'Timeline reminder sync failed: %{public}s',
        timelineReadCode(error as Error, 'REMINDER'));
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(0x0000, 'ToDone', `load content failed: ${JSON.stringify(err)}`);
      }
    });
  }
}
