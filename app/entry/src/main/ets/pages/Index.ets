import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { Colors, Radius, Space } from '../common/Theme';
import { Chip } from '../components/Chip';
import { MODULE_OPTIONS } from '../model/Defaults';
import { Matter, ModuleInstance, ModuleOption } from '../model/Types';
import { MatterStore } from '../store/MatterStore';

@Entry
@Component
struct Index {
  private store: MatterStore = MatterStore.getInstance();

  @State titleInput: string = '';
  @State descriptionInput: string = '';
  @State searchText: string = '';
  @State showArchived: boolean = false;
  @State matters: Matter[] = [];

  aboutToAppear(): void {
    const context = getContext(this) as common.UIAbilityContext;
    this.store.init(context);
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
      return matter.title.includes(keyword) || description.includes(keyword);
    });
  }

  private createMatter(): void {
    if (this.titleInput.trim().length === 0) {
      return;
    }
    this.store.addMatter({
      title: this.titleInput,
      description: this.descriptionInput
    });
    this.titleInput = '';
    this.descriptionInput = '';
    this.refresh();
  }

  build() {
    Navigation() {
      Column({ space: Space.normal }) {
        this.HeaderBar();
        this.CreatePanel();
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
        Text('管理长期存在、真正关心的事情')
          .fontSize(14)
          .fontColor(Colors.subText);
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start);

      Button('卡片预览')
        .fontSize(14)
        .fontColor(Colors.primary)
        .backgroundColor(Colors.primarySoft)
        .borderRadius(Radius.normal)
        .onClick(() => {
          router.pushUrl({ url: 'pages/WidgetPreview' });
        });
    }
    .width('100%');
  }

  @Builder
  private CreatePanel() {
    Column({ space: Space.normal }) {
      TextInput({ placeholder: '新事项名称', text: this.titleInput })
        .height(44)
        .fontSize(16)
        .backgroundColor(Colors.surfaceSoft)
        .borderRadius(Radius.normal)
        .onChange((value: string) => {
          this.titleInput = value;
        });

      TextInput({ placeholder: '说明，可不填', text: this.descriptionInput })
        .height(44)
        .fontSize(15)
        .backgroundColor(Colors.surfaceSoft)
        .borderRadius(Radius.normal)
        .onChange((value: string) => {
          this.descriptionInput = value;
        });

      Button('创建事项')
        .width('100%')
        .height(44)
        .fontSize(16)
        .fontColor(Color.White)
        .backgroundColor(Colors.primary)
        .borderRadius(Radius.normal)
        .onClick(() => this.createMatter());
    }
    .padding(Space.large)
    .backgroundColor(Colors.surface)
    .borderRadius(Radius.large)
    .border({
      width: 1,
      color: Colors.border
    });
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
        Button('重置演示数据')
          .fontSize(14)
          .fontColor(Colors.subText)
          .backgroundColor(Colors.surface)
          .borderRadius(Radius.normal)
          .border({
            width: 1,
            color: Colors.border
          })
          .onClick(() => {
            this.store.resetDemoData();
            this.refresh();
          });
      }
    }
  }

  @Builder
  private MatterList() {
    List({ space: Space.normal }) {
      ForEach(this.visibleMatters(), (matter: Matter, index: number) => {
        ListItem() {
          this.MatterRow(matter, index);
        }
      }, (matter: Matter) => matter.id);
    }
    .layoutWeight(1)
    .editMode(true)
    .onMove((from: number, to: number) => {
      const visible = this.visibleMatters();
      const moved = visible[from];
      if (moved) {
        this.store.moveMatterToActiveIndex(moved.id, to);
        this.refresh();
      }
    });
  }

  @Builder
  private MatterRow(matter: Matter, index: number) {
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
        ForEach(matter.enabledModules.slice(0, 5), (module: ModuleInstance) => {
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
            this.refresh();
          });
        Button('下移')
          .fontSize(14)
          .fontColor(Colors.primary)
          .backgroundColor(Colors.primarySoft)
          .borderRadius(Radius.normal)
          .margin({ right: Space.small, bottom: Space.small })
          .onClick(() => {
            this.store.moveMatterByDelta(matter.id, 1);
            this.refresh();
          });
        Button('关联上一项')
          .fontSize(14)
          .fontColor(index > 0 ? Colors.primary : Colors.subText)
          .backgroundColor(Colors.surfaceSoft)
          .borderRadius(Radius.normal)
          .margin({ right: Space.small, bottom: Space.small })
          .enabled(index > 0)
          .onClick(() => {
            this.store.clusterWithPrevious(matter.id);
            this.refresh();
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
              this.refresh();
            });
        }
        Button(matter.archived ? '恢复' : '归档')
          .fontSize(14)
          .fontColor(Colors.subText)
          .backgroundColor(Colors.surfaceSoft)
          .borderRadius(Radius.normal)
          .margin({ right: Space.small, bottom: Space.small })
          .onClick(() => {
            this.store.archiveMatter(matter.id, !matter.archived);
            this.refresh();
          });
        Button('删除')
          .fontSize(14)
          .fontColor(Colors.danger)
          .backgroundColor('#FFE7ED')
          .borderRadius(Radius.normal)
          .margin({ right: Space.small, bottom: Space.small })
          .onClick(() => {
            this.store.deleteMatter(matter.id);
            this.refresh();
          });
      }
    }
    .width('100%')
    .padding(Space.large)
    .backgroundColor(Colors.surface)
    .borderRadius(Radius.large)
    .border({
      width: 1,
      color: Colors.border
    });
  }

  private moduleText(module: ModuleInstance): string {
    const option = MODULE_OPTIONS.find((item: ModuleOption) => item.type === module.moduleType);
    return option ? option.label : '模块';
  }
}
