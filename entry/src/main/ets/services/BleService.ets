import { access, ble } from '@kit.ConnectivityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { WaterDevice } from '../model/WaterTypes';

const SERVICE_UUID = '0000F1F0-0000-1000-8000-00805F9B34FB';
const WRITE_CHAR_UUID = '0000F1F1-0000-1000-8000-00805F9B34FB';
const READ_CHAR_UUID = '0000F1F2-0000-1000-8000-00805F9B34FB';
const DOMAIN = 0x0000;
const TAG = 'WaterctlBLE';
const CONNECT_TIMEOUT_MS = 8000;
const PROFILE_STATE_DISCONNECTED = 0;
const PROFILE_STATE_CONNECTED = 2;

function normalizeUuid(uuid: string): string {
  return uuid.replace(/-/g, '').toUpperCase();
}

function isUuidEqual(a: string, b: string): boolean {
  return normalizeUuid(a) === normalizeUuid(b);
}

function createPayload(bytes: Array<number>): ArrayBuffer {
  const buffer = new ArrayBuffer(bytes.length);
  const view = new Uint8Array(buffer);
  for (let i = 0; i < bytes.length; i++) {
    view[i] = bytes[i];
  }
  return buffer;
}

const START_PROLOGUE: ArrayBuffer = createPayload([0xFE, 0xFE, 0x09, 0xB0, 0x01, 0x01, 0x00, 0x00]);
const END_PROLOGUE: ArrayBuffer = createPayload([0xFE, 0xFE, 0x09, 0xB3, 0x00, 0x00]);
const END_EPILOGUE: ArrayBuffer = createPayload([0xFE, 0xFE, 0x09, 0xB4, 0x00, 0x00]);
const BA_ACK: ArrayBuffer = createPayload([0xFE, 0xFE, 0x09, 0xBA, 0x00, 0x00]);

function decAsHex(n: number): number {
  if (n <= 0) {
    return 0;
  }
  return (n % 10) | (decAsHex(Math.floor(n / 10)) << 4);
}

function crc16changgong(str: string): number {
  let crc = 0x1017;
  for (let i = 0; i < str.length; i++) {
    crc ^= str.charCodeAt(i);
    for (let j = 0; j < 8; j++) {
      if ((crc & 0x0001) === 1) {
        crc >>= 1;
        crc ^= 0xA001;
      } else {
        crc >>= 1;
      }
    }
  }
  return crc;
}

function makeRandomUserId(): Array<number> {
  const randomId = Math.floor(Math.random() * 9999) + 1;
  const high = (randomId >> 8) & 0xFF;
  const low = randomId & 0xFF;
  return [decAsHex(high) & 0xFF, decAsHex(low) & 0xFF];
}

function makeDatetimeArray(): Array<number> {
  const now = new Date();
  const year = now.getFullYear() % 100;
  const month = now.getMonth() + 1;
  const day = now.getDate();
  const hours = now.getHours();
  const minutes = now.getMinutes();
  const seconds = now.getSeconds();
  return [
    decAsHex(year) & 0xFF,
    decAsHex(month) & 0xFF,
    decAsHex(day) & 0xFF,
    decAsHex(hours) & 0xFF,
    decAsHex(minutes) & 0xFF,
    decAsHex(seconds) & 0xFF
  ];
}

function makeStartEpilogue(deviceName: string): ArrayBuffer {
  const tail = deviceName.length > 5 ? deviceName.substring(deviceName.length - 5) : deviceName;
  const checksum = crc16changgong(tail);
  const randomId = makeRandomUserId();
  const dt = makeDatetimeArray();
  const payload: Array<number> = [
    0xFE, 0xFE, 0x09, 0xB2,
    0x01, checksum & 0xFF, (checksum >> 8) & 0xFF, 0xFF,
    0x00, randomId[0], randomId[1],
    dt[0], dt[1], dt[2], dt[3], dt[4], dt[5],
    0x0F, 0x27, 0x00
  ];
  return createPayload(payload);
}

class BleCharacteristicImpl implements ble.BLECharacteristic {
  serviceUuid: string = '';
  characteristicUuid: string = '';
  characteristicValue: ArrayBuffer = new ArrayBuffer(0);
  descriptors: Array<ble.BLEDescriptor> = [];
}

class WaterDeviceImpl implements WaterDevice {
  id: string = '';
  name: string = '';
  rssi: number = -127;
}

export class BleService {
  private readonly devices: Map<string, WaterDevice> = new Map<string, WaterDevice>();
  private readonly deviceFindCallback: (result: Array<ble.ScanResult>) => void;
  private connectedClient: ble.GattClientDevice | null = null;
  private connectedDevice: WaterDevice | null = null;
  private writeCharacteristic: ble.BLECharacteristic | null = null;
  private readCharacteristic: ble.BLECharacteristic | null = null;
  private writeType: ble.GattWriteType = ble.GattWriteType.WRITE;
  private isScanning: boolean = false;
  private listenerAttached: boolean = false;
  private connListenerAttached: boolean = false;
  private charListenerAttached: boolean = false;
  private isSessionActive: boolean = false;
  private permissionChecker: (() => Promise<void>) | null = null;
  private disconnectListener: (() => void) | null = null;
  private readonly connStateCallback: (state: ble.BLEConnectionChangeState) => void;
  private readonly characteristicChangeCallback: (characteristic: ble.BLECharacteristic) => void;
  private pendingConnectResolve: (() => void) | null = null;
  private pendingConnectReject: ((err: Error) => void) | null = null;
  private pendingConnectDeviceId: string = '';

  constructor() {
    this.deviceFindCallback = (result: Array<ble.ScanResult>) => {
      hilog.info(DOMAIN, TAG, 'BLEDeviceFind count=%{public}d', result.length);
      for (const item of result) {
        const rawName = item.deviceName ?? '';
        const name = rawName.trim();
        if (!name) {
          continue;
        }
        const id = item.deviceId ?? '';
        if (!id) {
          continue;
        }
        const rssi = item.rssi ?? -127;
        const device = new WaterDeviceImpl();
        device.id = id;
        device.name = name;
        device.rssi = rssi;
        this.devices.set(id, device);
        hilog.info(DOMAIN, TAG, 'Found device name=%{public}s rssi=%{public}d', name, rssi);
      }
    };
    this.connStateCallback = (state: ble.BLEConnectionChangeState) => {
      hilog.info(DOMAIN, TAG, 'BLEConnectionStateChange id=%{public}s state=%{public}d', state.deviceId, state.state);
      if (!this.pendingConnectResolve || !this.pendingConnectReject) {
        return;
      }
      if (state.deviceId !== this.pendingConnectDeviceId) {
        return;
      }
      if (state.state === PROFILE_STATE_CONNECTED) {
        const resolve = this.pendingConnectResolve;
        this.pendingConnectResolve = null;
        this.pendingConnectReject = null;
        this.pendingConnectDeviceId = '';
        resolve();
        return;
      }
      if (state.state === PROFILE_STATE_DISCONNECTED) {
        if (this.pendingConnectReject) {
          const reject = this.pendingConnectReject;
          this.pendingConnectResolve = null;
          this.pendingConnectReject = null;
          this.pendingConnectDeviceId = '';
          reject(new Error('BLE 连接已断开'));
          return;
        }
        this.isSessionActive = false;
        this.writeCharacteristic = null;
        this.readCharacteristic = null;
        this.connectedClient = null;
        this.connectedDevice = null;
        this.connListenerAttached = false;
        this.charListenerAttached = false;
        if (this.disconnectListener) {
          this.disconnectListener();
        }
      }
    };
    this.characteristicChangeCallback = (characteristic: ble.BLECharacteristic) => {
      this.handleDeviceNotification(characteristic).catch((err: Error) => {
        hilog.error(DOMAIN, TAG, 'handleDeviceNotification failed: %{public}s', err.message);
      });
    };
  }

  getDevices(): WaterDevice[] {
    const list: WaterDevice[] = [];
    this.devices.forEach((value: WaterDevice) => {
      list.push(value);
    });
    return list.sort((a: WaterDevice, b: WaterDevice) => b.rssi - a.rssi);
  }

  setPermissionChecker(checker: () => Promise<void>): void {
    this.permissionChecker = checker;
  }

  setDisconnectListener(listener: () => void): void {
    this.disconnectListener = listener;
  }

  async startScan(): Promise<void> {
    this.devices.clear();
    await this.stopScan();
    if (this.permissionChecker) {
      await this.permissionChecker();
    }
    const btState = access.getState();
    hilog.info(DOMAIN, TAG, 'Bluetooth state=%{public}d', btState);
    if (btState !== access.BluetoothState.STATE_ON) {
      access.enableBluetooth();
      throw new Error('蓝牙未开启，请先在弹窗中允许打开蓝牙后重试。');
    }
    ble.on('BLEDeviceFind', this.deviceFindCallback);
    this.listenerAttached = true;
    const filters: Array<ble.ScanFilter> | null = null;
    hilog.info(DOMAIN, TAG, 'startBLEScan with null filters');
    ble.startBLEScan(filters);
    this.isScanning = true;
  }

  async stopScan(): Promise<void> {
    if (this.isScanning) {
      ble.stopBLEScan();
      this.isScanning = false;
    }
    if (this.listenerAttached) {
      ble.off('BLEDeviceFind', this.deviceFindCallback);
      this.listenerAttached = false;
    }
  }

  async connect(device: WaterDevice): Promise<void> {
    await this.stopScan();
    await this.disconnect();
    this.connectedClient = ble.createGattClientDevice(device.id);
    this.connectedDevice = device;
    this.writeCharacteristic = null;
    this.readCharacteristic = null;
    this.writeType = ble.GattWriteType.WRITE;
    this.isSessionActive = false;
    this.connectedClient.on('BLEConnectionStateChange', this.connStateCallback);
    this.connListenerAttached = true;
    this.connectedClient.connect();
    await this.waitConnected(device.id);
    await this.resolveCharacteristics();
    if (!this.readCharacteristic) {
      throw new Error('未找到通知特征值');
    }
    await this.connectedClient.setCharacteristicChangeNotification(this.readCharacteristic, true);
    this.connectedClient.on('BLECharacteristicChange', this.characteristicChangeCallback);
    this.charListenerAttached = true;
  }

  async disconnect(): Promise<void> {
    if (!this.connectedClient) {
      return;
    }
    try {
      if (this.charListenerAttached) {
        this.connectedClient.off('BLECharacteristicChange', this.characteristicChangeCallback);
        this.charListenerAttached = false;
      }
      if (this.connListenerAttached) {
        this.connectedClient.off('BLEConnectionStateChange', this.connStateCallback);
        this.connListenerAttached = false;
      }
      if (this.readCharacteristic) {
        this.connectedClient.setCharacteristicChangeNotification(this.readCharacteristic, false);
      }
      this.connectedClient.disconnect();
      this.connectedClient.close();
    } finally {
      this.connectedClient = null;
      this.connectedDevice = null;
      this.writeCharacteristic = null;
      this.readCharacteristic = null;
      this.writeType = ble.GattWriteType.WRITE;
      this.isSessionActive = false;
      this.pendingConnectResolve = null;
      this.pendingConnectReject = null;
      this.pendingConnectDeviceId = '';
    }
  }

  getConnectedDevice(): WaterDevice | null {
    return this.connectedDevice;
  }

  private async writeWaterCommand(payload: ArrayBuffer): Promise<void> {
    if (!this.connectedClient) {
      throw new Error('Please connect device first.');
    }
    if (!this.writeCharacteristic) {
      await this.resolveCharacteristics();
    }
    if (!this.writeCharacteristic) {
      throw new Error('未找到可写入的水控特征值');
    }

    const characteristic = new BleCharacteristicImpl();
    characteristic.serviceUuid = this.writeCharacteristic.serviceUuid;
    characteristic.characteristicUuid = this.writeCharacteristic.characteristicUuid;
    characteristic.descriptors = this.writeCharacteristic.descriptors;
    characteristic.characteristicValue = payload;
    await this.writeWithFallback(characteristic);
  }

  async openWater(): Promise<void> {
    if (this.isSessionActive) {
      return;
    }
    await this.writeWaterCommand(START_PROLOGUE);
  }

  async closeWater(): Promise<void> {
    if (!this.isSessionActive) {
      return;
    }
    await this.writeWaterCommand(END_PROLOGUE);
  }

  async setPower(open: boolean): Promise<void> {
    if (open) {
      await this.openWater();
      return;
    }
    await this.closeWater();
  }

  private async waitConnected(deviceId: string): Promise<void> {
    await new Promise<void>((resolve, reject) => {
      this.pendingConnectResolve = resolve;
      this.pendingConnectReject = reject;
      this.pendingConnectDeviceId = deviceId;
      setTimeout(() => {
        if (!this.pendingConnectReject) {
          return;
        }
        const timeoutReject = this.pendingConnectReject;
        this.pendingConnectResolve = null;
        this.pendingConnectReject = null;
        this.pendingConnectDeviceId = '';
        timeoutReject(new Error('BLE 连接超时'));
      }, CONNECT_TIMEOUT_MS);
    });
  }

  private async resolveCharacteristics(): Promise<void> {
    if (!this.connectedClient) {
      throw new Error('BLE 客户端未连接');
    }
    const services = await this.connectedClient.getServices();
    for (const service of services) {
      if (!isUuidEqual(service.serviceUuid, SERVICE_UUID)) {
        continue;
      }
      const characteristics = service.characteristics;
      if (!characteristics) {
        continue;
      }
      for (const characteristic of characteristics) {
        if (isUuidEqual(characteristic.characteristicUuid, WRITE_CHAR_UUID)) {
          this.writeCharacteristic = characteristic;
          const props = characteristic.properties;
          const useNoRsp = props ? props.writeNoResponse === true : false;
          this.writeType = useNoRsp ? ble.GattWriteType.WRITE_NO_RESPONSE : ble.GattWriteType.WRITE;
          const supportsWrite = props ? props.write === true : false;
          const supportsWriteNoRsp = props ? props.writeNoResponse === true : false;
          hilog.info(DOMAIN, TAG, 'Resolved write char uuid=%{public}s supportsWrite=%{public}s supportsNoRsp=%{public}s defaultType=%{public}d',
            characteristic.characteristicUuid, `${supportsWrite}`, `${supportsWriteNoRsp}`, this.writeType);
          continue;
        }
        if (isUuidEqual(characteristic.characteristicUuid, READ_CHAR_UUID)) {
          this.readCharacteristic = characteristic;
          hilog.info(DOMAIN, TAG, 'Resolved read char uuid=%{public}s', characteristic.characteristicUuid);
        }
      }
    }
    if (!this.writeCharacteristic) {
      throw new Error('设备未发现目标写特征值');
    }
  }

  private async writeWithFallback(characteristic: ble.BLECharacteristic): Promise<void> {
    if (!this.connectedClient) {
      throw new Error('BLE 客户端未连接');
    }
    try {
      hilog.info(DOMAIN, TAG, 'writeCharacteristicValue uuid=%{public}s writeType=%{public}d',
        characteristic.characteristicUuid, this.writeType);
      await this.connectedClient.writeCharacteristicValue(characteristic, this.writeType);
    } catch (err) {
      const fallbackType = this.writeType === ble.GattWriteType.WRITE
        ? ble.GattWriteType.WRITE_NO_RESPONSE
        : ble.GattWriteType.WRITE;
      hilog.error(DOMAIN, TAG, 'Primary write failed, fallback writeType=%{public}d err=%{public}s',
        fallbackType, JSON.stringify(err));
      await this.connectedClient.writeCharacteristicValue(characteristic, fallbackType);
      this.writeType = fallbackType;
    }
  }

  private async handleDeviceNotification(characteristic: ble.BLECharacteristic): Promise<void> {
    if (!isUuidEqual(characteristic.characteristicUuid, READ_CHAR_UUID)) {
      return;
    }
    const value = characteristic.characteristicValue;
    if (!value || value.byteLength < 4) {
      return;
    }
    const payload = new Uint8Array(value);
    const frameType = payload[3];
    hilog.info(DOMAIN, TAG, 'RX frame type=0x%{public}x len=%{public}d', frameType, payload.length);
    if (frameType === 0xB0 || frameType === 0xB1) {
      const deviceName = this.connectedDevice ? this.connectedDevice.name : '';
      await this.writeWaterCommand(makeStartEpilogue(deviceName));
      return;
    }
    if (frameType === 0xB2) {
      this.isSessionActive = true;
      hilog.info(DOMAIN, TAG, 'Session started');
      return;
    }
    if (frameType === 0xB3) {
      this.isSessionActive = false;
      await this.writeWaterCommand(END_EPILOGUE);
      return;
    }
    if (frameType === 0xBA) {
      await this.writeWaterCommand(BA_ACK);
    }
  }
}

