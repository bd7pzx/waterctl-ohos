export interface LiveViewState {
  deviceId: string;
  deviceName: string;
  isWaterOpen: boolean;
  startAt: number;
  lastDurationSeconds: number;
}

export interface LiveViewStatePatch {
  deviceId?: string;
  deviceName?: string;
  isWaterOpen?: boolean;
  startAt?: number;
  lastDurationSeconds?: number;
}

class DefaultLiveViewState implements LiveViewState {
  deviceId: string = '';
  deviceName: string = '未连接';
  isWaterOpen: boolean = false;
  startAt: number = 0;
  lastDurationSeconds: number = 0;
}

export const DEFAULT_LIVE_VIEW_STATE: LiveViewState = new DefaultLiveViewState();

