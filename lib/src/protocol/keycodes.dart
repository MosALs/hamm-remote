/// Android key codes understood by the Android TV Remote Service
/// (`android.view.KeyEvent` values).
abstract final class KeyCode {
  static const int home = 3;
  static const int back = 4;
  static const int digit0 = 7; // digits 0-9 are 7..16
  static const int dpadUp = 19;
  static const int dpadDown = 20;
  static const int dpadLeft = 21;
  static const int dpadRight = 22;
  static const int dpadCenter = 23;
  static const int volumeUp = 24;
  static const int volumeDown = 25;
  static const int power = 26;
  static const int enter = 66;
  static const int del = 67;
  static const int menu = 82;
  static const int search = 84;
  static const int mediaPlayPause = 85;
  static const int mediaStop = 86;
  static const int mediaNext = 87;
  static const int mediaPrevious = 88;
  static const int mediaRewind = 89;
  static const int mediaFastForward = 90;
  static const int volumeMute = 164;
  static const int info = 165;
  static const int channelUp = 166;
  static const int channelDown = 167;
  static const int tv = 170;
  static const int guide = 172;
  static const int captions = 175;
  static const int settings = 176;
  static const int tvInput = 178;
  static const int tvTerrestrialDigital = 236;
  static const int tvSatellite = 237;
  static const int tvAntennaCable = 242;
  static const int tvInputHdmi1 = 243;
  static const int tvInputHdmi2 = 244;
  static const int tvInputHdmi3 = 245;
  static const int tvInputComposite1 = 247;
  static const int red = 183;
  static const int green = 184;
  static const int yellow = 185;
  static const int blue = 186;
  static const int mediaAudioTrack = 222;
  static const int lastChannel = 229;

  static int digit(int n) {
    RangeError.checkValueInInterval(n, 0, 9, 'n');
    return digit0 + n;
  }
}

/// Apps on the TV. Without ADB they open through deep links (launching by
/// package name over the remote link stopped working after a Play Store
/// change); with ADB they are started by package, like from the home screen.
enum TvApp {
  netflix('Netflix', 'com.netflix.ninja', 'netflix://'),
  youtube('YouTube', 'com.google.android.youtube.tv', 'https://www.youtube.com'),
  primeVideo('Prime Video', 'com.amazon.amazonvideo.livingroom', 'https://app.primevideo.com'),
  shahid('Shahid', 'net.mbc.shahidTV', 'https://shahid.mbc.net');

  const TvApp(this.label, this.packageName, this.launchLink);

  final String label;
  final String packageName;
  final String launchLink;

  /// ADB shell command that starts the app's TV launcher activity.
  String get adbLaunchCommand => 'monkey -p $packageName -c android.intent.category.LEANBACK_LAUNCHER 1';
}
