import { ConnectState, UsageRecord, WaterDevice } from '../model/WaterTypes';
import { BleService } from '../services/BleService';
import { UsageRepo } from '../storage/UsageRepo';
import { abilityAccessCtrl, common } from '@kit.AbilityKit';
import type { LiveViewStatePatch } from '../model/LiveViewState';
import { LiveViewStateRepo } from '../storage/LiveViewStateRepo';

function formatDuration(sec: number): string {
  const h = Math.floor(sec / 3600);
  const m = Math.floor((sec % 3600) / 60);
  const s = sec % 60;
  if (h > 0) {
    return `${h}h ${m}m ${s}s`;
  }
  return `${m}m ${s}s`;
}

function formatDate(timestamp: number): string {
  const d = new Date(timestamp);
  const pad = (n: number): string => `${n}`.padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
}

function signalLevel(rssi: number): number {
  if (rssi >= -55) {
    return 4;
  }
  if (rssi >= -70) {
    return 3;
  }
  if (rssi >= -85) {
    return 2;
  }
  if (rssi >= -100) {
    return 1;
  }
  return 0;
}

@Entry
@Component
struct Index {
  private readonly bleService: BleService = new BleService();
  private usageRepo: UsageRepo | null = null;
  private liveViewRepo: LiveViewStateRepo | null = null;
  private uiContext: UIContext = this.getUIContext();
  private scanTimerId: number = -1;
  private readonly atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();

  @State private connectState: ConnectState = ConnectState.IDLE;
  @State private devices: WaterDevice[] = [];
  @State private selectedDeviceId: string = '';
  @State private connectedDevice: WaterDevice | null = null;
  @State private isWaterOpen: boolean = false;
  @State private activeStartAt: number = 0;
  @State private statusText: string = '未连接';
  @State private usageHistory: UsageRecord[] = [];
  @State private errorMessage: string = '';

  aboutToAppear(): void {
    const abilityContext = this.uiContext.getHostContext() as common.UIAbilityContext;
    this.bleService.setPermissionChecker(async (): Promise<void> => {
      await this.atManager.requestPermissionsFromUser(abilityContext, [
        'ohos.permission.ACCESS_BLUETOOTH',
        'ohos.permission.DISCOVER_BLUETOOTH',
        'ohos.permission.LOCATION'
      ]);
    });
    this.bleService.setDisconnectListener(() => {
      this.isWaterOpen = false;
      this.activeStartAt = 0;
      this.connectedDevice = null;
      this.connectState = ConnectState.IDLE;
      this.statusText = '连接已断开';
      this.errorMessage = '设备连接中断，已自动重置';
      this.updateLiveViewState({
        deviceId: '',
        deviceName: '未连接',
        isWaterOpen: false,
        startAt: 0
      }).catch((_err: Error) => {});
      this.startScan().catch((err: Error) => {
        this.errorMessage = `扫描失败: ${err.message}`;
      });
    });
    if (!this.usageRepo) {
      this.usageRepo = new UsageRepo(abilityContext);
    }
    if (!this.liveViewRepo) {
      this.liveViewRepo = new LiveViewStateRepo(abilityContext);
    }
    this.loadHistory().catch((err: Error) => {
      this.errorMessage = `加载记录失败: ${err.message}`;
    });
    this.startScan().catch((err: Error) => {
      this.errorMessage = `扫描失败: ${err.message}`;
    });
  }

  aboutToDisappear(): void {
    this.stopScan().catch((_err: Error) => {});
  }

  private async loadHistory(): Promise<void> {
    if (!this.usageRepo) {
      return;
    }
    this.usageHistory = await this.usageRepo.list();
  }

  private async startScan(): Promise<void> {
    this.errorMessage = '';
    this.connectState = ConnectState.SCANNING;
    this.statusText = '扫描设备中';
    await this.bleService.startScan();
    this.devices = this.bleService.getDevices();

    if (this.scanTimerId >= 0) {
      clearInterval(this.scanTimerId);
    }
    this.scanTimerId = setInterval(() => {
      this.devices = this.bleService.getDevices();
      if (!this.selectedDeviceId && this.devices.length > 0) {
        this.selectedDeviceId = this.devices[0].id;
      }
    }, 1000);
  }

  private async stopScan(): Promise<void> {
    await this.bleService.stopScan();
    if (this.scanTimerId >= 0) {
      clearInterval(this.scanTimerId);
      this.scanTimerId = -1;
    }
    if (this.connectState === ConnectState.SCANNING) {
      this.connectState = ConnectState.IDLE;
      this.statusText = '未连接';
    }
  }

  private getSelectedDevice(): WaterDevice | null {
    for (const device of this.devices) {
      if (device.id === this.selectedDeviceId) {
        return device;
      }
    }
    return null;
  }

  private async connectSelectedDevice(): Promise<void> {
    const selected = this.getSelectedDevice();
    if (!selected) {
      this.errorMessage = '请先选择一个设备';
      return;
    }
    this.connectState = ConnectState.CONNECTING;
    this.statusText = '连接中';
    this.errorMessage = '';
    try {
      await this.bleService.connect(selected);
      this.connectedDevice = selected;
      this.connectState = ConnectState.CONNECTED;
      this.statusText = `已连接 ${selected.name}`;
      await this.updateLiveViewState({
        deviceId: selected.id,
        deviceName: selected.name
      });
    } catch (err) {
      this.connectState = ConnectState.IDLE;
      this.statusText = '连接失败';
      this.errorMessage = `连接失败: ${JSON.stringify(err)}`;
    }
  }

  private async disconnectDevice(): Promise<void> {
    this.errorMessage = '';
    if (this.isWaterOpen) {
      await this.closeWater();
    }
    await this.bleService.disconnect();
    this.connectedDevice = null;
    this.connectState = ConnectState.IDLE;
    this.statusText = '未连接';
    await this.updateLiveViewState({
      deviceId: '',
      deviceName: '未连接',
      isWaterOpen: false,
      startAt: 0
    });
    await this.startScan();
  }

  private async openWater(): Promise<void> {
    this.errorMessage = '';
    await this.bleService.openWater();
    this.isWaterOpen = true;
    this.activeStartAt = Date.now();
    this.statusText = '开水中';
    await this.updateLiveViewState({
      isWaterOpen: true,
      startAt: this.activeStartAt,
      lastDurationSeconds: 0
    });
  }

  private async closeWater(): Promise<void> {
    this.errorMessage = '';
    await this.bleService.closeWater();
    if (this.usageRepo && this.connectedDevice && this.activeStartAt > 0) {
      await this.usageRepo.add(this.connectedDevice.name, this.activeStartAt, Date.now());
      await this.loadHistory();
    }
    const closedAt = Date.now();
    const endedDuration = this.activeStartAt > 0 ? Math.max(0, Math.floor((closedAt - this.activeStartAt) / 1000)) : 0;
    this.isWaterOpen = false;
    this.activeStartAt = 0;
    this.statusText = this.connectedDevice ? `已连接 ${this.connectedDevice.name}` : '未连接';
    await this.updateLiveViewState({
      isWaterOpen: false,
      startAt: 0,
      lastDurationSeconds: endedDuration
    });
  }

  private async clearHistory(): Promise<void> {
    if (!this.usageRepo) {
      return;
    }
    await this.usageRepo.clear();
    this.usageHistory = [];
  }

  private async updateLiveViewState(patch: LiveViewStatePatch): Promise<void> {
    if (!this.liveViewRepo) {
      return;
    }
    const current = await this.liveViewRepo.get();
    if (patch.deviceId !== undefined) {
      current.deviceId = patch.deviceId;
    }
    if (patch.deviceName !== undefined) {
      current.deviceName = patch.deviceName;
    }
    if (patch.isWaterOpen !== undefined) {
      current.isWaterOpen = patch.isWaterOpen;
    }
    if (patch.startAt !== undefined) {
      current.startAt = patch.startAt;
    }
    if (patch.lastDurationSeconds !== undefined) {
      current.lastDurationSeconds = patch.lastDurationSeconds;
    }
    await this.liveViewRepo.set(current);
  }

  @Builder
  private buildSignal(level: number): void {
    Row({ space: 3 }) {
      ForEach([1, 2, 3, 4], (idx: number) => {
        Column()
          .width(5)
          .height(5 + idx * 4)
          .backgroundColor(idx <= level ? $r('app.color.signal_active') : $r('app.color.signal_inactive'))
          .borderRadius(2)
      });
    }
    .alignItems(VerticalAlign.Bottom)
    .height(24);
  }

  @Builder
  private buildHeader(): void {
    Column({ space: 6 }) {
      Text('Waterctl')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'));
      Text(this.statusText)
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'));
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%');
  }

  @Builder
  private buildDevices(): void {
    Column({ space: 8 }) {
      Text('附近设备')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'));

      List({ space: 8 }) {
        ForEach(this.devices, (item: WaterDevice) => {
          ListItem() {
            Row({ space: 10 }) {
              Radio({ value: item.id, group: 'ble-group' })
                .checked(this.selectedDeviceId === item.id)
                .onChange((isOn: boolean) => {
                  if (isOn) {
                    this.selectedDeviceId = item.id;
                  }
                });

              Column({ space: 2 }) {
                Text(item.name)
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'));
                Text(`${item.id} · RSSI ${item.rssi}`)
                  .fontSize(11)
                  .fontColor($r('app.color.text_secondary'));
              }
              .layoutWeight(1);

              this.buildSignal(signalLevel(item.rssi));
            }
            .padding(12)
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius(12);
          }
        }, (item: WaterDevice) => item.id);
      }
      .height(200);
    }
  }

  @Builder
  private buildControls(): void {
    Column({ space: 10 }) {
      if (this.connectState !== ConnectState.CONNECTED) {
        Button('连接')
          .enabled(this.devices.length > 0 && this.connectState !== ConnectState.CONNECTING)
          .width('100%')
          .height(44)
          .backgroundColor($r('app.color.primary_btn'))
          .fontColor($r('app.color.btn_text'))
          .onClick(() => {
            this.connectSelectedDevice().catch((err: Error) => {
              this.errorMessage = `连接失败: ${err.message}`;
            });
          });
      } else {
        Row({ space: 8 }) {
          Button('开水')
            .enabled(!this.isWaterOpen)
            .layoutWeight(1)
            .height(42)
            .backgroundColor($r('app.color.primary_btn'))
            .fontColor($r('app.color.btn_text'))
            .onClick(() => {
              this.openWater().catch((err: Error) => {
                this.errorMessage = `开水失败: ${err.message}`;
              });
            });

          Button('关水')
            .enabled(this.isWaterOpen)
            .layoutWeight(1)
            .height(42)
            .backgroundColor($r('app.color.warn_btn'))
            .fontColor($r('app.color.btn_text'))
            .onClick(() => {
              this.closeWater().catch((err: Error) => {
                this.errorMessage = `关水失败: ${err.message}`;
              });
            });

          Button('断开')
            .layoutWeight(1)
            .height(42)
            .backgroundColor($r('app.color.neutral_btn'))
            .fontColor($r('app.color.btn_text'))
            .onClick(() => {
              this.disconnectDevice().catch((err: Error) => {
                this.errorMessage = `断开失败: ${err.message}`;
              });
            });
        }
      }
    }
  }

  @Builder
  private buildHistory(): void {
    Column({ space: 8 }) {
      Row() {
        Text('使用记录')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'));
        Blank();
        Button('清空记录')
          .height(30)
          .fontSize(12)
          .backgroundColor($r('app.color.neutral_btn'))
          .fontColor($r('app.color.btn_text'))
          .onClick(() => {
            this.clearHistory().catch((err: Error) => {
              this.errorMessage = `清空失败: ${err.message}`;
            });
          });
      }
      .width('100%');

      List({ space: 8 }) {
        ForEach(this.usageHistory, (record: UsageRecord) => {
          ListItem() {
            Column({ space: 2 }) {
              Text(`${record.deviceName} · ${formatDuration(record.durationSeconds)}`)
                .fontSize(14)
                .fontColor($r('app.color.text_primary'));
              Text(`${formatDate(record.startAt)} -> ${formatDate(record.endAt)}`)
                .fontSize(11)
                .fontColor($r('app.color.text_secondary'));
            }
            .alignItems(HorizontalAlign.Start)
            .padding(12)
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius(12);
          }
        }, (record: UsageRecord) => record.id);
      }
      .layoutWeight(1);
    }
  }

  build() {
    Column({ space: 12 }) {
      this.buildHeader();
      this.buildDevices();
      this.buildControls();
      if (this.errorMessage) {
        Text(this.errorMessage)
          .fontSize(12)
          .fontColor($r('app.color.error_text'));
      }
      this.buildHistory();
    }
    .padding({
      top: 20,
      right: 16,
      bottom: 28,
      left: 16
    })
    .backgroundColor($r('app.color.page_bg'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .width('100%')
    .height('100%');
  }
}

