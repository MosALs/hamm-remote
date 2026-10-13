import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/services.dart';

/// Apps on the phone that can cast to the TV themselves.
///
/// Every package here must also be listed under `<queries>` in
/// AndroidManifest.xml, or Android 11+ hides it from this app.
enum CastApp {
  youtube('YouTube', 'com.google.android.youtube', 'Opens YouTube; tap its Cast icon'),
  netflix('Netflix', 'com.netflix.mediaclient', 'Opens Netflix on your phone'),
  photos('Google Photos', 'com.google.android.apps.photos', 'Show photos and videos'),
  shahid('Shahid', 'net.mbc.shahid', 'Opens Shahid on your phone');

  const CastApp(this.label, this.packageName, this.hint);

  final String label;
  final String packageName;
  final String hint;
}

/// What happened when asking the phone to start casting.
enum CastResult { opened, openedGoogleHome, unsupported }

const String googleHomePackage = 'com.google.android.apps.chromecast.app';
const int _newTask = 0x10000000; // Intent.FLAG_ACTIVITY_NEW_TASK

/// Opens the phone's screen-cast picker, where the TV (Chromecast built in)
/// appears. Android 14+ offers casting a single app from the same picker.
Future<CastResult> openScreenCast() async {
  if (!Platform.isAndroid) return CastResult.unsupported;
  for (final action in const ['android.settings.CAST_SETTINGS', 'android.settings.WIFI_DISPLAY_SETTINGS']) {
    if (await _launch(AndroidIntent(action: action, flags: const [_newTask]))) return CastResult.opened;
  }
  if (await _launch(_launcherIntent(googleHomePackage))) return CastResult.openedGoogleHome;
  return CastResult.unsupported;
}

/// Opens [app] on the phone, or its Play Store page when it is not installed.
/// Returns false when neither could be opened.
Future<bool> openPhoneApp(CastApp app) async {
  if (!Platform.isAndroid) return false;
  if (await _launch(_launcherIntent(app.packageName))) return true;
  return _launch(AndroidIntent(
    action: 'action_view',
    data: 'market://details?id=${app.packageName}',
    flags: const [_newTask],
  ));
}

AndroidIntent _launcherIntent(String packageName) => AndroidIntent(
      action: 'android.intent.action.MAIN',
      category: 'android.intent.category.LAUNCHER',
      package: packageName,
      flags: const [_newTask],
    );

/// Starts [intent] only when something on the phone handles it. Checking
/// first matters: the plugin drops the package from an unresolvable intent
/// and would otherwise show a chooser of every app.
Future<bool> _launch(AndroidIntent intent) async {
  try {
    if (await intent.canResolveActivity() != true) return false;
    await intent.launch();
    return true;
  } on PlatformException {
    return false;
  }
}
