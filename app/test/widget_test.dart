// Smoke tests for shared spec widgets. The full app can't be pumped here —
// IkhlasApp requires a live Firebase instance (Firebase.initializeApp), which
// integration tests cover on-device instead.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ikhlas/core/theme/app_theme.dart';
import 'package:ikhlas/core/theme/widgets.dart';

void main() {
  testWidgets('PrimaryCta renders its label and fires onPressed',
      (WidgetTester tester) async {
    var tapped = false;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: PrimaryCta(label: 'Begin my application', onPressed: () => tapped = true),
      ),
    ));

    expect(find.text('Begin my application'), findsOneWidget);
    await tester.tap(find.byType(PrimaryCta));
    expect(tapped, isTrue);
  });

  testWidgets('PrimaryCta shows a spinner while loading',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: const Scaffold(
        body: PrimaryCta(label: 'Begin my application', loading: true),
      ),
    ));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Begin my application'), findsNothing);
  });
}
