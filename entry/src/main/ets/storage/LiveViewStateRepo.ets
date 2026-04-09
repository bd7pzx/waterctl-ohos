import { preferences } from '@kit.ArkData';
import { DEFAULT_LIVE_VIEW_STATE, LiveViewState } from '../model/LiveViewState';

const STORE_NAME = 'water_live_view_store';
const LIVE_STATE_KEY = 'live_view_state';

class LiveViewStateRecord implements LiveViewState {
  deviceId: string = '';
  deviceName: string = '';
  isWaterOpen: boolean = false;
  startAt: number = 0;
  lastDurationSeconds: number = 0;
}

export class LiveViewStateRepo {
  private readonly context: Context;

  constructor(context: Context) {
    this.context = context;
  }

  private async getStore(): Promise<preferences.Preferences> {
    return preferences.getPreferences(this.context, STORE_NAME);
  }

  async get(): Promise<LiveViewState> {
    const store: preferences.Preferences = await this.getStore();
    const raw = await store.get(LIVE_STATE_KEY, JSON.stringify(DEFAULT_LIVE_VIEW_STATE)) as string;
    try {
      const data = JSON.parse(raw) as LiveViewState;
      const state = new LiveViewStateRecord();
      state.deviceId = data.deviceId || '';
      state.deviceName = data.deviceName || DEFAULT_LIVE_VIEW_STATE.deviceName;
      state.isWaterOpen = !!data.isWaterOpen;
      state.startAt = Number(data.startAt) || 0;
      state.lastDurationSeconds = Number(data.lastDurationSeconds) || 0;
      return state;
    } catch (_err) {
      const fallback = new LiveViewStateRecord();
      fallback.deviceId = DEFAULT_LIVE_VIEW_STATE.deviceId;
      fallback.deviceName = DEFAULT_LIVE_VIEW_STATE.deviceName;
      fallback.isWaterOpen = DEFAULT_LIVE_VIEW_STATE.isWaterOpen;
      fallback.startAt = DEFAULT_LIVE_VIEW_STATE.startAt;
      fallback.lastDurationSeconds = DEFAULT_LIVE_VIEW_STATE.lastDurationSeconds;
      return fallback;
    }
  }

  async set(state: LiveViewState): Promise<void> {
    const store: preferences.Preferences = await this.getStore();
    await store.put(LIVE_STATE_KEY, JSON.stringify(state));
    await store.flush();
  }
}

