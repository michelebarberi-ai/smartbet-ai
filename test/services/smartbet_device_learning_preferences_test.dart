import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartbet_ai_new/services/smartbet_device_learning_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('primo avvio: opt-in locale OFF', () async {
    final preferences = const SmartBetDeviceLearningPreferences();
    expect(await preferences.loadEnabled(), isFalse);
  });

  test('opt-in rimane memorizzato su questo dispositivo', () async {
    const writer = SmartBetDeviceLearningPreferences();
    expect(await writer.saveEnabled(true), isTrue);
    const reader = SmartBetDeviceLearningPreferences();
    expect(await reader.loadEnabled(), isTrue);
  });

  test('disattivazione persiste sul dispositivo', () async {
    const preferences = SmartBetDeviceLearningPreferences();
    expect(await preferences.saveEnabled(true), isTrue);
    expect(await preferences.saveEnabled(false), isTrue);
    expect(await preferences.loadEnabled(), isFalse);
  });

  test('una preferenza non booleana non attiva il learning', () async {
    SharedPreferences.setMockInitialValues({
      SmartBetDeviceLearningPreferences.storageKey: 'true',
    });
    const preferences = SmartBetDeviceLearningPreferences();
    // SharedPreferences.getBool puo' lanciare: deve fallire chiuso.
    expect(await preferences.loadEnabled(), isFalse);
  });

  test('errore di lettura: opt-in rimane OFF', () async {
    final preferences = SmartBetDeviceLearningPreferences(
      preferencesLoader: () async => throw StateError('Errore lettura'),
    );
    expect(await preferences.loadEnabled(), isFalse);
  });

  test('errore di scrittura: opt-in non confermato', () async {
    final preferences = SmartBetDeviceLearningPreferences(
      preferencesLoader: () async => throw StateError('Errore scrittura'),
    );
    expect(await preferences.saveEnabled(true), isFalse);
  });
}
