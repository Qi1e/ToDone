import { describe, beforeEach, it, expect } from '@ohos/hypium';
import { MatterStore } from '../../../main/ets/store/MatterStore';
import { ModuleType } from '../../../main/ets/model/Types';

export default function matterStoreTest() {
  describe('MatterStore', () => {
    const store = MatterStore.getInstance();

    beforeEach(() => {
      store.resetDemoData();
    });

    it('creates, updates, archives, and deletes a matter', 0, () => {
      const matter = store.addMatter({
        title: '  模拟事项  ',
        description: '初始说明'
      });

      expect(matter.title).assertEqual('模拟事项');
      expect(store.activeMatters().some((item) => item.id === matter.id)).assertEqual(true);

      store.updateMatter(matter.id, '更新后的事项', '更新后的说明');
      expect(store.findMatter(matter.id)?.title).assertEqual('更新后的事项');
      expect(store.findMatter(matter.id)?.description).assertEqual('更新后的说明');

      store.archiveMatter(matter.id, true);
      expect(store.activeMatters().some((item) => item.id === matter.id)).assertEqual(false);
      expect(store.archivedMatters().some((item) => item.id === matter.id)).assertEqual(true);

      store.deleteMatter(matter.id);
      expect(store.findMatter(matter.id)).assertEqual(undefined);
    });

    it('reorders active matters while keeping archived matters out of the active order', 0, () => {
      const first = store.activeMatters();
      const movedId = first[2].id;

      store.archiveMatter(first[1].id, true);
      store.moveMatterToActiveIndex(movedId, 0);

      const activeIds = store.activeMatters().map((matter) => matter.id);
      expect(activeIds[0]).assertEqual(movedId);
      expect(activeIds[1]).assertEqual(first[0].id);
      expect(store.archivedMatters()[0].id).assertEqual(first[1].id);
    });

    it('joins matters into a weak cluster and cleans the cluster after deletion', 0, () => {
      const left = store.addMatter({ title: '簇事项 A' });
      const right = store.addMatter({ title: '簇事项 B' });
      store.createOrJoinCluster(right.id, left.id);

      expect(left.clusterId).assertEqual(right.clusterId);
      store.deleteMatter(left.id);
      store.deleteMatter(right.id);

      const nextLeft = store.addMatter({ title: '新簇事项 A' });
      const nextRight = store.addMatter({ title: '新簇事项 B' });
      store.createOrJoinCluster(nextRight.id, nextLeft.id);

      expect(store.clusterColor(nextLeft.clusterId)).assertEqual('#00A88B');
    });

    it('records events, counters, progress, and checklist changes', 0, () => {
      const matter = store.addMatter({ title: '模块事项' });
      store.toggleModule(matter.id, ModuleType.EventRecord);
      store.toggleModule(matter.id, ModuleType.Counter);
      store.toggleModule(matter.id, ModuleType.Progress);
      store.toggleModule(matter.id, ModuleType.Checklist);

      store.addEventRecord(matter.id);
      expect(store.todayEventCount(matter.id)).assertEqual(1);

      store.addCounterEntry(matter.id, 10);
      store.markDailyOnce(matter.id);
      store.markDailyOnce(matter.id);
      expect(store.counterToday(matter.id)).assertEqual(11);
      expect(store.counterTotal(matter.id)).assertEqual(11);

      store.setProgressPercent(matter.id, 140);
      expect(store.getProgressPercent(matter.id)).assertEqual(100);

      store.addChecklistItem(matter.id, '第一项');
      store.addChecklistItem(matter.id, '第二项');
      const items = store.checklistItemsFor(matter.id);
      store.toggleChecklistItem(items[0].id);
      expect(store.checklistProgressText(matter.id)).assertEqual('1 / 2');
      store.deleteChecklistItem(items[0].id);
      expect(store.checklistProgressText(matter.id)).assertEqual('0 / 1');
    });

    it('limits summary card selection to three matters and allows clearing it', 0, () => {
      const initial = store.selectedSummaryCardMatterIds();
      expect(initial.length).assertEqual(3);

      const extra = store.addMatter({ title: '汇总卡片第四项' });
      store.toggleSummaryCardMatter(extra.id);
      expect(store.selectedSummaryCardMatterIds().length).assertEqual(3);
      expect(store.selectedSummaryCardMatterIds().includes(extra.id)).assertEqual(true);

      store.selectedSummaryCardMatterIds().forEach((id) => store.toggleSummaryCardMatter(id));
      expect(store.selectedSummaryCardMatterIds().length).assertEqual(0);
    });
  });
}
