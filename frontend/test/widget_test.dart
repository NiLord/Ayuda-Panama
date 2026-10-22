import 'package:flutter_test/flutter_test.dart';
import 'package:ayuda_los_santos/main.dart';
import 'package:ayuda_los_santos/screens/onboarding_profile_screen.dart';

void main() {
  testWidgets('App renders onboarding profile screen properly', (WidgetTester tester) async {
    await tester.pumpWidget(const AyudaLosSantosApp(
      initialScreen: OnboardingProfileScreen(),
    ));

    expect(find.text('Ayuda Los Santos'), findsOneWidget);
    expect(find.text('Tu Nombre Completo *'), findsOneWidget);
    expect(find.text('Tu Cédula de Identidad Personal *'), findsOneWidget);
    expect(find.text('Teléfono de Contacto (+507...) *'), findsOneWidget);
    expect(find.text('Comenzar'), findsOneWidget);
  });
}
