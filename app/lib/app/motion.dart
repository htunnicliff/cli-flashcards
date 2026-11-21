/// Motion preferences: "Reduce motion" keeps fades but drops movement.
library;

import 'package:material_ui/material_ui.dart';

import '../core/models.dart';
import 'app_state.dart';

/// Whether movement should be dropped, from the setting or the device.
bool reducedMotion(BuildContext context) {
  final scope = context.getInheritedWidgetOfExactType<AppScope>();
  final pref = scope?.notifier?.settings.motion ?? MotionPreference.system;
  return switch (pref) {
    MotionPreference.reduce => true,
    MotionPreference.full => false,
    MotionPreference.system => MediaQuery.disableAnimationsOf(context),
  };
}

/// A transition length. Kept under reduced motion, so fades still play.
Duration motionDuration(BuildContext context, int milliseconds) =>
    Duration(milliseconds: milliseconds);
