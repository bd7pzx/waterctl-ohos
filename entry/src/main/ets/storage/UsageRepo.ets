import { preferences } from '@kit.ArkData';
import { UsageRecord } from '../model/WaterTypes';

const STORE_NAME = 'water_usage_store';
const HISTORY_KEY = 'usage_history';
const MAX_HISTORY_SIZE = 200;

function createRecordId(deviceName: string, startAt: number): string {
  return `${deviceName}_${startAt}`;
}

export class UsageRepo {
  private readonly context: Context;

  constructor(context: Context) {
    this.context = context;
  }

  private async getStore(): Promise<preferences.Preferences> {
    return preferences.getPreferences(this.context, STORE_NAME);
  }

  private createUsageRecord(): UsageRecord {
    return new UsageRecord();
  }

  private createEmptyList(): UsageRecord[] {
    return [];
  }

  private parseList(raw: string): UsageRecord[] {
    try {
      return JSON.parse(raw) as UsageRecord[];
    } catch (_err) {
      return this.createEmptyList();
    }
  }

  private sortByStartDesc(records: UsageRecord[]): UsageRecord[] {
    return records.sort((a: UsageRecord, b: UsageRecord) => b.startAt - a.startAt);
  }

  async list(): Promise<UsageRecord[]> {
    const store: preferences.Preferences = await this.getStore();
    const raw = await store.get(HISTORY_KEY, '[]') as string;
    const parsed = this.parseList(raw);
    return this.sortByStartDesc(parsed);
  }

  async add(deviceName: string, startAt: number, endAt: number): Promise<UsageRecord> {
    const record = this.createUsageRecord();
    record.id = createRecordId(deviceName, startAt);
    record.deviceName = deviceName;
    record.startAt = startAt;
    record.endAt = endAt;
    record.durationSeconds = Math.max(0, Math.floor((endAt - startAt) / 1000));
    const store: preferences.Preferences = await this.getStore();
    const existing: UsageRecord[] = await this.list();
    const next: UsageRecord[] = [];
    next.push(record);
    for (const item of existing) {
      if (next.length >= MAX_HISTORY_SIZE) {
        break;
      }
      next.push(item);
    }
    await store.put(HISTORY_KEY, JSON.stringify(next));
    await store.flush();
    return record;
  }

  async clear(): Promise<void> {
    const store: preferences.Preferences = await this.getStore();
    await store.put(HISTORY_KEY, '[]');
    await store.flush();
  }
}
