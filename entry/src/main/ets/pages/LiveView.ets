import { LiveViewStateRepo } from '../storage/LiveViewStateRepo';
import { common } from '@kit.AbilityKit';

function formatDuration(sec: number): string {
  const h = Math.floor(sec / 3600);
  const m = Math.floor((sec % 3600) / 60);
  const s = sec % 60;
  if (h > 0) {
    return `${h}h ${m}m ${s}s`;
  }
  return `${m}m ${s}s`;
}

@Entry
@Component
export struct LiveView {
  private uiContext: UIContext = this.getUIContext();
  private stateRepo: LiveViewStateRepo | null = null;
  private tickerId: number = -1;

  @State private statusText: string = '未开水';
  @State private deviceText: string = '设备: 未连接';
  @State private durationText: string = '时长: 0m 0s';

  aboutToAppear(): void {
    const abilityContext = this.uiContext.getHostContext() as common.UIAbilityContext;
    if (!this.stateRepo) {
      this.stateRepo = new LiveViewStateRepo(abilityContext);
    }
    this.refresh().catch((_err: Error) => {});
    if (this.tickerId >= 0) {
      clearInterval(this.tickerId);
    }
    this.tickerId = setInterval(() => {
      this.refresh().catch((_err: Error) => {});
    }, 1000);
  }

  aboutToDisappear(): void {
    if (this.tickerId >= 0) {
      clearInterval(this.tickerId);
      this.tickerId = -1;
    }
  }

  private async refresh(): Promise<void> {
    if (!this.stateRepo) {
      return;
    }
    const state = await this.stateRepo.get();
    const now = Date.now();
    const durationSec = state.isWaterOpen && state.startAt > 0
      ? Math.max(0, Math.floor((now - state.startAt) / 1000))
      : state.lastDurationSeconds;
    this.statusText = state.isWaterOpen ? '开水中' : '未开水';
    this.deviceText = `设备: ${state.deviceName || '未连接'}`;
    this.durationText = `时长: ${formatDuration(durationSec)}`;
  }

  build() {
    Column({ space: 8 }) {
      Text('水控器实况')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor('#FFFFFF');

      Text(this.statusText)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF');

      Text(this.deviceText)
        .fontSize(12)
        .fontColor('#E9EEFF');

      Text(this.durationText)
        .fontSize(12)
        .fontColor('#E9EEFF');
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor('#1C4FD7')
    .borderRadius(12);
  }
}

