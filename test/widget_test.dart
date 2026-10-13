import 'package:flutter_test/flutter_test.dart';
import 'package:haam_remote/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('first launch shows the key-preparation splash', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const HaamRemoteApp());
    expect(find.text('Preparing a secure key for pairing…'), findsOneWidget);
  });
}
