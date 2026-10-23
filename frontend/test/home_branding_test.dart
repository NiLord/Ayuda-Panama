import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:ayuda_los_santos/screens/home_screen.dart';

void main() {
  testWidgets('HomeScreen renders responsive SVG logo on mobile and tablet', (WidgetTester tester) async {
    // 1. Mobile screen test (iPhone 390x844)
    tester.view.physicalSize = const Size(390 * 2.0, 844 * 2.0);
    tester.view.devicePixelRatio = 2.0;

    await tester.pumpWidget(
      const MaterialApp(
        home: HomeScreen(),
      ),
    );
    await tester.pumpAndSettle();

    final svgFinder = find.byType(SvgPicture);
    expect(svgFinder, findsOneWidget);

    final SvgPicture phoneSvg = tester.widget(svgFinder);
    expect(phoneSvg.semanticsLabel, 'Logo Ayuda Panamá');
    expect(phoneSvg.height, inInclusiveRange(100.0, 160.0));

    // 2. Tablet screen test (iPad 820x1180)
    tester.view.physicalSize = const Size(820 * 2.0, 1180 * 2.0);
    tester.view.devicePixelRatio = 2.0;

    await tester.pumpWidget(
      const MaterialApp(
        home: HomeScreen(),
      ),
    );
    await tester.pumpAndSettle();

    final SvgPicture tabletSvg = tester.widget(find.byType(SvgPicture));
    expect(tabletSvg.height, inInclusiveRange(180.0, 240.0));

    // Reset view
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  });
}
