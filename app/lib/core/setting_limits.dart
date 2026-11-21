/// Allowed ranges for scheduling settings, from `src/core/scheduler/settings.ts`.
library;

class SettingLimits {
  const SettingLimits(this.min, this.max, this.step);
  final num min;
  final num max;
  final num step;

  /// Brings a value into range and onto its step.
  num normalize(num value) {
    final stepped = (value / step).round() * step;
    final clamped = stepped.clamp(min, max);
    return num.parse(clamped.toStringAsFixed(2));
  }
}

const desiredRetentionLimits = SettingLimits(0.7, 0.99, 0.01);
const newCardsPerDayLimits = SettingLimits(0, 999, 1);
const maxReviewsPerDayLimits = SettingLimits(0, 9999, 1);
const dayRolloverHourLimits = SettingLimits(0, 23, 1);
const leechThresholdLimits = SettingLimits(2, 99, 1);
