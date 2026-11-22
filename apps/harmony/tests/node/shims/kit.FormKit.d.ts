import { Want } from './kit.AbilityKit';
export namespace formBindingData {
  interface FormBindingData { data: Object }
  function createFormBindingData(obj?: Object | string): FormBindingData;
}
export namespace formInfo {
  enum FormParam { IDENTITY_KEY = 'ohos.extra.param.key.form_identity', DIMENSION_KEY = 'ohos.extra.param.key.form_dimension' }
  enum FormDimension { Dimension_1_2 = 1, Dimension_2_2 = 2, Dimension_2_4 = 3, Dimension_4_4 = 4 }
  enum FormState { UNKNOWN = -1, DEFAULT = 0, READY = 1 }
}
export namespace formProvider {
  function updateForm(formId: string, data: formBindingData.FormBindingData): Promise<void>;
}
export class FormExtensionAbility {
  context: { filesDir: string };
  onAddForm(want: Want): formBindingData.FormBindingData;
  onUpdateForm(formId: string): void;
  onRemoveForm(formId: string): void;
  onFormEvent(formId: string, message: string): void;
  onAcquireFormState(want: Want): formInfo.FormState;
}
