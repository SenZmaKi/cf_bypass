import 'package:flutter_test/flutter_test.dart';

import 'package:cf_bypass_example/main.dart';

void main() {
  testWidgets('CF bypass example renders', (tester) async {
    await tester.pumpWidget(const CfBypassApp());

    expect(find.text('CF BYPASS LAB'), findsOneWidget);
  });
}
