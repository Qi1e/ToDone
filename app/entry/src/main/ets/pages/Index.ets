import { common } from '@kit.AbilityKit';
import { unifiedDataChannel } from '@kit.ArkData';
import { router } from '@kit.ArkUI';
import { Colors, Radius, Space } from '../common/Theme';
import { Chip } from '../components/Chip';
import { MODULE_OPTIONS } from '../model/Defaults';
import { Matter, ModuleInstance, ModuleOption, ModuleType } from '../model/Types';
import { MatterStore } from '../store/MatterStore';
import { refreshKnownCards } from '../widget/CardRefresh';

const MATTER_DRAG_TYPE: string = 'ApplicationDefined.ToDoneMatter';

@Entry
@Component
struct Index {
  private store: MatterStore = MatterStore.getInstance();

  @State searchText: string = '';
  @State showArchived: boolean = false;
  @State matters: Matter[] = [];
  @State pendingDeleteMatterId: string = '';
  @State pendingReset: boolean = false;
  @State feedbackText: string = '';
  @State dragSourceMatterId: string = '';
  @State dragTargetMatterId: string = '';

  aboutToAppear(): void {
    const context = getContext(this) as common.UIAbilityContext;
    this.store.init(context);
    this.refresh();
    refreshKnownCards(this.store);
  }

  onPageShow(): void {
    this.refresh();
  }

  private refresh(): void {
    this.matters = this.showArchived ? this.store.archivedMatters() : this.store.activeMatters();
  }

  private visibleMatters(): Matter[] {
    const keyword = this.searchText.trim();
    if (keyword.length === 0) {
      return this.matters;
    }
    return this.matters.filter((matter: Matter) => {
      const description = matter.description ?? '';
      const note = this.store.getNote(matter.id);
      return matter.title.includes(keyword) || description.includes(keyword) || note.includes(keyword);
    });
  }

  private refreshCards(prefix: string): void {
    const result = refreshKnownCards(this.store);
    this.feedbackText = `${prefix}。${result.message}`;
  }

  private startMatterDrag(matterId: string, event: DragEvent): DragItemInfo {
    this.dragSourceMatterId = matterId;
    this.dragTargetMatterId = '';
    const record = new unifiedDataChannel.UnifiedRecord(MATTER_DRAG_TYPE, matterId);
    event.setData(new unifiedDataChannel.UnifiedData(record));
    return {};
  }

  private finishMatterDrop(targetId: string, event: DragEvent): void {
    try {
      const records = event.getData().getRecords();
      const record = records.length > 0 ? records[0] : undefined;
      const value = record ? record.getValue() : undefined;
      const sourceId = record && record.getType() === MATTER_DRAG_TYPE && typeof value === 'string' ? value : '';
      if (sourceId.length > 0 && sourceId !== targetId) {
        this.store.createOrJoinCluster(sourceId, targetId);
        this.refresh();
        this.refreshCards('已建立关联');
      }
    } catch (error) {
    }
    this.clearMatterDrag();
  }

  private clearMatterDrag(): void {
    this.dragSourceMatterId = '';
    this.dragTargetMatterId = '';
  }

  build() {
    Navigation() {
      Column({ space: Space.normal }) {
        this.HeaderBar();
        this.SearchBar();
        this.MatterList();
      }
      .width('100%')
      .height('100%')
      .padding({
        left: Space.large,
        right: Space.large,
        top: Space.large,
        bottom: Space.large
      })
      .backgroundColor(Colors.page);
    }
    .title('ToDone')
    .mode(NavigationMode.Stack);
  }

  @Builder
  private HeaderBar() {
    Row() {
      Column({ space: 4 }) {
        Text('事项')
          .fontSize(30)
          .fontWeight(FontWeight.Bold)
          .fontColor(Colors.text);
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start);

      Row({ space: Space.small }) {
        Button('新建')
          .fontSize(14)
          .fontColor(Color.White)
          .backgroundColor(Colors.primary)
          .borderRadius(Radius.normal)
          .onClick(() => {
            router.pushUrl({ url: 'pages/CreateMatter' });
          });
        Button('卡片')
          .fontSize(14)
          .fontColor(Colors.primary)
          .backgroundColor(Colors.primarySoft)
          .borderRadius(Radius.normal)
          .onClick(() => {
            router.pushUrl({ url: 'pages/WidgetPreview' });
          });
      }
    }
    .width('100%');
  }

  @Builder
  private SearchBar() {
    Column({ space: Space.small }) {
      TextInput({ placeholder: '搜索事项', text: this.searchText })
        .height(42)
        .fontSize(15)
        .backgroundColor(Colors.surface)
        .borderRadius(Radius.normal)
        .onChange((value: string) => {
          this.searchText = value;
        });

      Row({ space: Space.small }) {
        Button(this.showArchived ? '显示未归档' : '显示归档')
          .fontSize(14)
          .fontColor(Colors.primary)
          .backgroundColor(Colors.primarySoft)
          .borderRadius(Radius.normal)
          .onClick(() => {
            this.showArchived = !this.showArchived;
            this.refresh();
          });
        Button(this.pendingReset ? '确认重置' : '重置演示数据')
          .fontSize(14)
          .fontColor(this.pendingReset ? Color.White : Colors.subText)
          .backgroundColor(this.pendingReset ? Colors.danger : Colors.surface)
          .borderRadius(Radius.normal)
          .border({
            width: 1,
            color: Colors.border
          })
          .onClick(() => {
            if (!this.pendingReset) {
              this.pendingReset = true;
              this.feedbackText = '再次点击确认重置演示数据';
              return;
            }
            this.store.resetDemoData();
            this.pendingReset = false;
            this.pendingDeleteMatterId = '';
            this.refresh();
            this.refreshCards('已重置演示数据');
          });
      }

      if (this.feedbackText.length > 0) {
        Text(this.feedbackText)
          .fontSize(13)
          .fontColor(Colors.subText)
          .width('100%');
      }
    }
  }

  @Builder
  private MatterList() {
    if (this.visibleMatters().length === 0) {
      Column({ space: Space.small }) {
        Text(this.showArchived ? '还没有归档事项' : '还没有事项')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(Colors.text);
      }
      .width('100%')
      .padding(Space.large)
      .backgroundColor(Colors.surface)
      .borderRadius(Radius.large)
      .border({ width: 1, color: Colors.border });
    } else {
      List({ space: Space.normal }) {
        ForEach(this.visibleMatters(), (matter: Matter) => {
          ListItem() {
            this.MatterRow(matter);
          }
        }, (matter: Matter) => matter.id);
      }
      .layoutWeight(1);
    }
  }

  @Builder
  private MatterRow(matter: Matter) {
    Column({ space: Space.normal }) {
      Row() {
        Column()
          .width(6)
          .height(62)
          .backgroundColor(this.store.clusterColor(matter.clusterId))
          .borderRadius(3);

        Column({ space: 5 }) {
          Row() {
            Text(matter.title)
              .fontSize(19)
              .fontWeight(FontWeight.Bold)
              .fontColor(Colors.text)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1);
            if (matter.clusterId) {
              Text('弱关联')
                .fontSize(12)
                .fontColor(Colors.primary)
                .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                .backgroundColor(Colors.primarySoft)
                .borderRadius(Radius.small);
            }
          }

          Text(matter.description ?? '未填写说明')
            .fontSize(14)
            .fontColor(Colors.subText)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });

          Text(this.store.moduleSummary(matter))
            .fontSize(13)
            .fontColor(Colors.subText)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
        }
        .margin({ left: Space.normal })
        .layoutWeight(1);
      }
      .width('100%');

      Row({ space: Space.small }) {
        ForEach(this.visibleModulesFor(matter).slice(0, 5), (module: ModuleInstance) => {
          Chip({ text: this.moduleText(module), selected: true });
        }, (module: ModuleInstance) => module.id);
      }

      Flex({ wrap: FlexWrap.Wrap }) {
        Button('打开')
          .fontSize(14)
          .fontColor(Color.White)
          .backgroundColor(Colors.primary)
          .borderRadius(Radius.normal)
          .margin({ right: Space.small, bottom: Space.small })
          .onClick(() => {
            router.pushUrl({
              url: 'pages/MatterDetail',
              params: { matterId: matter.id }
            });
          });
        Button('上移')
          .fontSize(14)
          .fontColor(Colors.primary)
          .backgroundColor(Colors.primarySoft)
          .borderRadius(Radius.normal)
          .margin({ right: Space.small, bottom: Space.small })
          .onClick(() => {
            this.store.moveMatterByDelta(matter.id, -1);
            this.pendingDeleteMatterId = '';
            this.refresh();
            this.refreshCards('已调整排序');
          });
        Button('下移')
          .fontSize(14)
          .fontColor(Colors.primary)
          .backgroundColor(Colors.primarySoft)
          .borderRadius(Radius.normal)
          .margin({ right: Space.small, bottom: Space.small })
          .onClick(() => {
            this.store.moveMatterByDelta(matter.id, 1);
            this.pendingDeleteMatterId = '';
            this.refresh();
            this.refreshCards('已调整排序');
          });
        if (matter.clusterId) {
          Button('移出簇')
            .fontSize(14)
            .fontColor(Colors.warning)
            .backgroundColor('#FFF0E8')
            .borderRadius(Radius.normal)
            .margin({ right: Space.small, bottom: Space.small })
            .onClick(() => {
              this.store.detachCluster(matter.id);
              this.pendingDeleteMatterId = '';
              this.refresh();
              this.refreshCards('已移出弱关联');
            });
        }
        Button(matter.archived ? '恢复' : '归档')
          .fontSize(14)
          .fontColor(Colors.subText)
          .backgroundColor(Colors.surfaceSoft)
          .borderRadius(Radius.normal)
          .margin({ right: Space.small, bottom: Space.small })
          .onClick(() => {
            const wasArchived = matter.archived;
            this.store.archiveMatter(matter.id, !matter.archived);
            this.pendingDeleteMatterId = '';
            this.refresh();
            this.refreshCards(wasArchived ? '已恢复事项' : '已归档事项');
          });
        Button(this.pendingDeleteMatterId === matter.id ? '确认删除' : '删除')
          .fontSize(14)
          .fontColor(this.pendingDeleteMatterId === matter.id ? Color.White : Colors.danger)
          .backgroundColor(this.pendingDeleteMatterId === matter.id ? Colors.danger : '#FFE7ED')
          .borderRadius(Radius.normal)
          .margin({ right: Space.small, bottom: Space.small })
          .onClick(() => {
            if (this.pendingDeleteMatterId !== matter.id) {
              this.pendingDeleteMatterId = matter.id;
              this.feedbackText = `再次点击确认删除「${matter.title}」`;
              return;
            }
            this.store.deleteMatter(matter.id);
            this.pendingDeleteMatterId = '';
            this.refresh();
            this.refreshCards('已删除事项');
          });
      }
    }
    .width('100%')
    .padding(Space.large)
    .backgroundColor(this.dragTargetMatterId === matter.id ? Colors.primarySoft : Colors.surface)
    .borderRadius(Radius.large)
    .border({
      width: this.dragTargetMatterId === matter.id ? 2 : 1,
      color: this.dragTargetMatterId === matter.id ? Colors.primary : Colors.border
    })
    .draggable(true)
    .onDragStart((event: DragEvent) => this.startMatterDrag(matter.id, event))
    .onDragEnter(() => {
      if (this.dragSourceMatterId !== matter.id) {
        this.dragTargetMatterId = matter.id;
      }
    })
    .onDragLeave(() => {
      if (this.dragTargetMatterId === matter.id) {
        this.dragTargetMatterId = '';
      }
    })
    .onDrop((event: DragEvent) => this.finishMatterDrop(matter.id, event))
    .onDragEnd(() => this.clearMatterDrag());
  }

  private moduleText(module: ModuleInstance): string {
    const option = MODULE_OPTIONS.find((item: ModuleOption) => item.type === module.moduleType);
    return option ? option.label : '信息';
  }

  private visibleModulesFor(matter: Matter): ModuleInstance[] {
    return matter.enabledModules.filter((module: ModuleInstance) => {
      return module.moduleType !== ModuleType.Countdown && module.moduleType !== ModuleType.Progress;
    });
  }
}
