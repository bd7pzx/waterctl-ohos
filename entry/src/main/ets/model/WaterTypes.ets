export interface WaterDevice {
  id: string;
  name: string;
  rssi: number;
}

export class UsageRecord {
  id: string = '';
  deviceName: string = '';
  startAt: number = 0;
  endAt: number = 0;
  durationSeconds: number = 0;
}

export enum ConnectState {
  IDLE = 'idle',
  SCANNING = 'scanning',
  CONNECTING = 'connecting',
  CONNECTED = 'connected'
}

