import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/main.dart';

void main() {
  testWidgets('shows the GTFS import screen before a feed is loaded', (
    tester,
  ) async {
    await tester.pumpWidget(const TransitDeskApp());

    expect(find.text('A clearer view of\nevery journey.'), findsOneWidget);
    expect(find.text('Choose GTFS ZIP'), findsOneWidget);
    expect(find.text('Explore stops'), findsOneWidget);
    expect(find.text('Trace routes'), findsOneWidget);
  });
}
