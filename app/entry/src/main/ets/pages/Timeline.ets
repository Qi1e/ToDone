import { HomeScreen } from '../components/HomeScreen';
import { HomeTab } from '../components/HomeNavigation';

@Entry
@Component
struct Timeline {
  @State private foreground: boolean = true;
  private handleBack: () => boolean = () => false;

  onPageShow(): void { this.foreground = true; }
  onPageHide(): void { this.foreground = false; }
  onBackPress(): boolean { return this.handleBack(); }

  build() {
    Column() {
      HomeScreen({ initialTab: HomeTab.Timeline, foreground: this.foreground,
        registerBack: (handler: () => boolean) => { this.handleBack = handler; } })
    }.width('100%').height('100%')
  }
}
