export namespace vibrator {
  interface VibratePreset { type: 'preset'; effectId: string; count?: number }
  interface VibrateAttribute { id?: number; usage: string }
  function isSupportEffectSync(effectId: string): boolean;
  function startVibration(effect: VibratePreset, attribute: VibrateAttribute): Promise<void>;
}
