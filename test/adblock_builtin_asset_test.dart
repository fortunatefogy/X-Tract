import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linky/services/adblock/adblock_defaults.dart';
import 'package:linky/services/adblock/adblock_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('built-in OISD list is bundled and compiles', () async {
    final text = await rootBundle.loadString(AdblockDefaults.builtInOisdAsset);
    expect(text.length, greaterThan(100000));
    final engine = AdblockEngine.build([text]);
    expect(engine.networkRuleCount, greaterThan(10000));
  });
}
