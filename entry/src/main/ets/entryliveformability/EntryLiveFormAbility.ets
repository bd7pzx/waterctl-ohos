import LiveFormExtensionAbility from '@ohos.app.form.LiveFormExtensionAbility';
import type { LiveFormInfo } from '@ohos.app.form.LiveFormExtensionAbility';
import type UIExtensionContentSession from '@ohos.app.ability.UIExtensionContentSession';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x1001;
const TAG = 'EntryLiveFormAbility';

export default class EntryLiveFormAbility extends LiveFormExtensionAbility {
  onLiveFormCreate(_liveFormInfo: LiveFormInfo, session: UIExtensionContentSession): void {
    try {
      session.loadContent('pages/LiveView');
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'onLiveFormCreate loadContent failed: %{public}s', JSON.stringify(err));
    }
  }

  onLiveFormDestroy(_liveFormInfo: LiveFormInfo): void {}
}

