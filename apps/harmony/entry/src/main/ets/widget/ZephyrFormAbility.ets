/*
 * 服务卡片提供方（契约 §17.c）：卡片进程只读 UI 进程写下的快照（CardStore），不加载引擎、不起 VPN。
 * - onAddForm：记下卡片 id（UI 进程据此主动 updateForm），回当前快照；
 * - onUpdateForm：定时 / 零点刷新（form_config scheduledUpdateTime 00:00，§11 E44），日期变了“今日”归零；
 * - onRemoveForm：去掉 id。
 * 电源按钮与卡片点击经 postCardAction router 直达 EntryAbility（不经 URL，契约 §17.e③），由 App 执行并算作用户手动操作。
 */
import { FormExtensionAbility, formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CardSnapshots } from './CardSnapshot';
import { CardStore } from './CardStore';

const DOMAIN: number = 0x5A50;
const TAG: string = 'ZephyrForm';

export default class ZephyrFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    const dir = this.context.filesDir;
    const params = want.parameters;
    const id = params !== undefined ? params[formInfo.FormParam.IDENTITY_KEY] as string : undefined;
    const dim = params !== undefined ? params[formInfo.FormParam.DIMENSION_KEY] as number : undefined;
    const wide = dim === formInfo.FormDimension.Dimension_2_4;
    if (id !== undefined) {
      try {
        CardStore.saveIds(dir, CardSnapshots.withId(CardStore.ids(dir), id, wide));
      } catch (e) {
        hilog.error(DOMAIN, TAG, 'save form id failed: %{public}s', String(e));
      }
    }
    return this.current(wide);
  }

  onUpdateForm(formId: string): void {
    formProvider.updateForm(formId, this.current(CardSnapshots.wideOf(CardStore.ids(this.context.filesDir), formId))).catch((e: Error) => {
      hilog.error(DOMAIN, TAG, 'updateForm failed: %{public}s', String(e));
    });
  }

  onRemoveForm(formId: string): void {
    const dir = this.context.filesDir;
    try {
      CardStore.saveIds(dir, CardSnapshots.withoutId(CardStore.ids(dir), formId));
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'remove form id failed: %{public}s', String(e));
    }
  }

  onFormEvent(formId: string, message: string): void {
    // 卡片只用 router 事件，不用 message。
  }

  onAcquireFormState(want: Want): formInfo.FormState {
    return formInfo.FormState.READY;
  }

  private current(wide: boolean): formBindingData.FormBindingData {
    const s = CardSnapshots.forDisplay(CardStore.snapshot(this.context.filesDir), Date.now());
    return formBindingData.createFormBindingData(CardSnapshots.binding(s, wide));
  }
}
