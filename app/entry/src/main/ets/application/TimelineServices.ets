import { timelineReadCode } from '../domain/TimelineReadError';
import { common } from '@kit.AbilityKit';
import { TimelineService } from '../contracts/TimelineService';
import { DefaultTimelineService } from '../domain/DefaultTimelineService';
import { PreferencesStateStorage } from '../store/PreferencesStateStorage';

export class TimelineServices {
  private static service: TimelineService | undefined = undefined;

  static get(context: common.UIAbilityContext): TimelineService {
    if (TimelineServices.service === undefined) {
      let storage: PreferencesStateStorage;
      try {
        storage = new PreferencesStateStorage(context, 'todone_timeline', 'timeline_blocks_v1');
      } catch (error) {
        throw new Error(timelineReadCode(error as Error, 'OPEN'));
      }
      TimelineServices.service = new DefaultTimelineService(storage);
    }
    return TimelineServices.service;
  }
}
