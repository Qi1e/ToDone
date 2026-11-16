import { common } from '@kit.AbilityKit';
import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { notificationManager } from '@kit.NotificationKit';
import { formatDateTime } from '../common/DateFormat';
import { TimelineBlock } from '../contracts/TimelineService';
import { planTimelineReminders, TimelinePlannedReminder } from '../domain/TimelineReminderPlan';

// 这个通知 ID 区间仅供 Timeline 代理提醒使用，系统返回的 reminderId 用于撤销。
// 以系统的有效提醒为准；即使写入成功后进程立即终止，重开仍能找回这些提醒。
const NOTIFICATION_BASE: number = 0x54000000;
const NOTIFICATION_RANGE: number = 0x01000000;
const APP_REMINDER_LIMIT: number = 30;
const NOT_ENABLED: string = '系统通知未开启，日程提醒尚未送达系统。可在设置中允许 ToDone 通知后重试。';

interface PendingReminder {
  entry: TimelinePlannedReminder;
  request: reminderAgentManager.ReminderRequestCalendar;
}

function notificationId(key: string, used: Set<number>): number {
  let hash = 0;
  for (let i = 0; i < key.length; i++) hash = (hash * 31 + key.charCodeAt(i)) % NOTIFICATION_RANGE;
  let id = NOTIFICATION_BASE + hash;
  while (used.has(id)) id = NOTIFICATION_BASE + (id - NOTIFICATION_BASE + 1) % NOTIFICATION_RANGE;
  used.add(id);
  return id;
}

function isTimelineId(id?: number): boolean {
  return id !== undefined && id >= NOTIFICATION_BASE && id < NOTIFICATION_BASE + NOTIFICATION_RANGE;
}

function localTime(stamp: number): reminderAgentManager.LocalDateTime {
  const d = new Date(stamp);
  return { year: d.getFullYear(), month: d.getMonth() + 1, day: d.getDate(), hour: d.getHours(),
    minute: d.getMinutes(), second: d.getSeconds() };
}

function requestFor(context: common.UIAbilityContext, entry: TimelinePlannedReminder, id: number):
  reminderAgentManager.ReminderRequestCalendar {
  return {
    reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
    dateTime: localTime(entry.fireAt), title: entry.title, content: formatDateTime(entry.startAt) + ' 开始',
    notificationId: id, ringDuration: 0, snoozeTimes: 0,
    actionButton: [{ title: '关闭', type: reminderAgentManager.ActionButtonType.ACTION_BUTTON_TYPE_CLOSE }],
    wantAgent: { pkgName: context.abilityInfo.bundleName, abilityName: context.abilityInfo.name }
  };
}

function matches(actual: reminderAgentManager.ReminderRequest, expected: reminderAgentManager.ReminderRequestCalendar): boolean {
  if (actual.reminderType !== expected.reminderType || actual.title !== expected.title ||
    actual.content !== expected.content) return false;
  const time = (actual as reminderAgentManager.ReminderRequestCalendar).dateTime;
  const target = expected.dateTime;
  // API 12 的 ReminderInfo 只保证返回基础字段；通知 ID 也编码了触发时间与时区。
  return time === undefined || time.year === target.year && time.month === target.month && time.day === target.day &&
    time.hour === target.hour && time.minute === target.minute && (time.second ?? 0) === (target.second ?? 0);
}

async function cancel(id: number): Promise<void> {
  try {
    await reminderAgentManager.cancelReminder(id);
  } catch (err) {
    // 枚举之后刚好到期也算撤销完成。
    const error = err as BusinessError;
    if (error.code !== 1700003) return Promise.reject(error);
  }
}

async function notificationsEnabled(context: common.UIAbilityContext, ask: boolean): Promise<boolean> {
  if (await notificationManager.isNotificationEnabled()) return true;
  if (!ask) return false;
  await notificationManager.requestEnableNotification(context);
  return notificationManager.isNotificationEnabled();
}

function failure(code: number): string {
  if (code === 1600004 || code === 1700001) return NOT_ENABLED;
  if (code === 201 || code === 801) return '当前设备未开放 ToDone 的系统代理提醒，请检查应用的代理提醒资格。';
  if (code === 1700002) return '系统未接收全部日程提醒，设备名额已满或尚未向 ToDone 开放代理提醒。可在时间线中重试。';
  return '系统提醒尚未同步完成，请在时间线中重试。';
}

export class TimelineReminders {
  private static pending: Promise<string> = Promise.resolve('');

  static sync(context: common.UIAbilityContext, blocks: TimelineBlock[], askPermission: boolean = false): Promise<string> {
    const run = (): Promise<string> => TimelineReminders.reconcile(context, blocks, askPermission);
    TimelineReminders.pending = TimelineReminders.pending.then(run, run);
    return TimelineReminders.pending;
  }

  private static async reconcile(context: common.UIAbilityContext, blocks: TimelineBlock[], ask: boolean): Promise<string> {
    let needsReminders = false;
    try {
      const plan = planTimelineReminders(blocks, Date.now(), APP_REMINDER_LIMIT);
      needsReminders = plan.entries.length > 0;
      const active = await reminderAgentManager.getAllValidReminders();
      const owned = active.filter((item: reminderAgentManager.ReminderInfo) => isTimelineId(item.reminderReq.notificationId));
      needsReminders = needsReminders || owned.length > 0;
      const available = Math.max(0, APP_REMINDER_LIMIT - (active.length - owned.length));
      const used = new Set<number>();
      const desired = new Map<number, PendingReminder>();
      for (const entry of plan.entries.slice(0, available)) {
        const fireDate = new Date(entry.fireAt);
        const id = notificationId(entry.key + '/' + entry.fireAt + '/' + fireDate.getTimezoneOffset(), used);
        desired.set(id, { entry: entry, request: requestFor(context, entry, id) });
      }
      for (const item of owned) {
        const id = item.reminderReq.notificationId as number;
        const pending = desired.get(id);
        if (pending && matches(item.reminderReq, pending.request)) desired.delete(id);
        else await cancel(item.reminderId);
      }
      if (plan.entries.length === 0) return '';
      if (!await notificationsEnabled(context, ask)) return NOT_ENABLED;
      if (available === 0) return '应用的系统提醒名额已满，释放名额后请重试。';
      let missed = false;
      for (const item of desired.values()) {
        // 授权弹窗尚未关闭时已到点的提醒，不能当作已排入系统。
        if (item.entry.fireAt <= Date.now()) missed = true;
        else await reminderAgentManager.publishReminder(item.request);
      }
      if (missed) return '有提醒在等待授权或同步期间已到点，请在详情中调整提醒时间。';
      if (plan.hasMore || plan.entries.length > available) {
        return '已优先安排最近的 ' + Math.min(available, plan.entries.length) + ' 次提醒，后续提醒将在再次打开应用时补排。';
      }
      return '';
    } catch (err) {
      const code = (err as BusinessError).code;
      if (!needsReminders && (code === 201 || code === 801)) return '';
      return failure(code);
    }
  }
}
