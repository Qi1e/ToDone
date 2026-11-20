import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { TimelineBlock } from '../contracts/TimelineService';
import { timelineReadCode } from '../domain/TimelineReadError';
import { TimelineServices } from '../application/TimelineServices';
import { TimelineReminders } from '../application/TimelineReminders';
import { MatterServices } from '../application/MatterServices';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(0x0000, 'ToDone', 'EntryAbility created');
  }

  onForeground(): void {
    MatterServices.initialize(this.context).catch(() => {
      hilog.error(0x0000, 'ToDone', 'Matter reload failed on foreground');
    });
    this.refreshTimelineReminders();
  }

  private async refreshTimelineReminders(): Promise<void> {
    let blocks: TimelineBlock[];
    try {
      blocks = TimelineServices.get(this.context).list();
    } catch (error) {
      hilog.error(0x0000, 'ToDone', 'Timeline load failed on foreground: %{public}s',
        timelineReadCode(error as Error, 'INIT'));
      return;
    }
    try {
      const status = await TimelineReminders.sync(this.context, blocks);
      if (status) hilog.info(0x0000, 'ToDone', 'Timeline reminder sync: %{public}s', status);
    } catch (error) {
      hilog.warn(0x0000, 'ToDone', 'Timeline reminder sync failed: %{public}s', timelineReadCode(error as Error, 'REMINDER'));
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

