// Avatars animate wherever a mascot appears, and the system's reduce-motion
// setting makes them still. On a screen with several avatars they all ride one
// shared clock: with a scope injected, the clock reports the same holders count
// as there are avatars; with the real scope, the whole screen runs one ticker.

import 'package:dsh_app/state/mascot_clock.dart';
import 'package:dsh_app/ui/bots/bot_avatar.dart';
import 'package:dsh_app/ui/im/im_companions_page.dart';
import 'package:dsh_app/ui/im/im_messages_page.dart';
import 'package:dsh_app/ui/mascots/mascot_avatar.dart' show MascotPainter;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../bots/support.dart' show FakeDsBotTransport, dsBotOverrides;
import '../../chat/support/harness.dart' show loadTestFonts, testApp, usePhoneView;

Future<void> frames(WidgetTester tester, [int count = 12]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(loadTestFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Opens the partners tab inside a clock scope. [clock] injects a clock the
  /// test drives; leaving it out uses the real scope, which runs one ticker.
  Future<MascotClock?> open(WidgetTester tester, {MascotClock? clock, bool reduceMotion = false}) async {
    usePhoneView(tester);
    if (clock != null) addTearDown(clock.dispose);
    final page = ImCompanionsPage(onOpenBot: (_) {});
    await tester.pumpWidget(testApp(
      MascotClockScope(
        clock: clock,
        child: reduceMotion
            ? MediaQuery(data: const MediaQueryData(disableAnimations: true), child: page)
            : page,
      ),
      overrides: dsBotOverrides(FakeDsBotTransport()),
    ));
    await frames(tester);
    return clock;
  }

  test('the clock turns elapsed time into a phase and never runs back', () {
    final clock = MascotClock();
    addTearDown(clock.dispose);
    clock.advanceTo(const Duration(milliseconds: 550));
    expect(clock.phaseOf(const Duration(milliseconds: 1100)), closeTo(0.5, 0.001));
    clock.advanceTo(const Duration(milliseconds: 2200));
    expect(clock.phaseOf(const Duration(milliseconds: 1100)), closeTo(0, 0.001));

    // A frame timestamp that goes backwards must not replay the animation.
    clock.advanceTo(const Duration(milliseconds: 100));
    expect(clock.elapsed, const Duration(milliseconds: 2200));
  });

  testWidgets('every companion avatar animates by default', (tester) async {
    await open(tester);
    final avatars = tester.widgetList<BotAvatar>(find.byType(BotAvatar)).toList();
    expect(avatars, isNotEmpty);
    expect(avatars.every((avatar) => avatar.animate), isTrue);
  });

  testWidgets('the real scope runs one ticker for the whole screen', (tester) async {
    await open(tester);
    expect(find.byType(BotAvatar), findsNWidgets(3));
    // One avatar per ticker would report three.
    expect(tester.binding.transientCallbackCount, lessThanOrEqualTo(1));
  });

  List<MascotPainter> mascotPainters(WidgetTester tester) => [
    for (final paint in tester.widgetList<CustomPaint>(
      find.descendant(of: find.byType(BotAvatar), matching: find.byType(CustomPaint)),
    ))
      if (paint.painter is MascotPainter) paint.painter! as MascotPainter,
  ];

  testWidgets('all avatars ride the same injected clock', (tester) async {
    final clock = MascotClock();
    await open(tester, clock: clock);
    expect(find.byType(BotAvatar), findsNWidgets(3));

    // Chief and Writer are mascots; Coder carries a host photo, so it draws a
    // picture instead of a painter. Two mascots, one clock.
    final painters = mascotPainters(tester);
    expect(painters.length, 2);
    expect(painters.every((painter) => identical(painter.clock, clock)), isTrue);
    expect(clock.holders, painters.length);

    // Half of the lively period: every avatar reads the same phase from the clock.
    clock.advanceTo(const Duration(milliseconds: 550));
    await tester.pump();
    final after = mascotPainters(tester);
    expect(after.length, 2);
    expect(after.map((painter) => painter.period).toSet().length, 1);
    for (final painter in after) {
      expect(clock.phaseOf(painter.period), closeTo(0.5, 0.001));
    }
  });

  testWidgets('reduced motion releases the clock and stops the ticker', (tester) async {
    final clock = MascotClock();
    await open(tester, clock: clock, reduceMotion: true);
    expect(clock.holders, 0);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('a covered page releases the clock', (tester) async {
    final clock = MascotClock();
    await open(tester, clock: clock);
    expect(clock.holders, 2, reason: 'two mascots; the third Bot shows a photo');

    final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
    navigator.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: SizedBox.expand())));
    await frames(tester);
    expect(clock.holders, 0);
  });

  testWidgets('message list avatars animate too', (tester) async {
    usePhoneView(tester);
    await tester.pumpWidget(testApp(
      MascotClockScope(
        child: ImMessagesPage(onOpenBot: (_) {}, onOpenRoom: (_) {}, onGoDiscover: () {}),
      ),
      overrides: dsBotOverrides(FakeDsBotTransport()),
    ));
    await frames(tester);
    final avatars = tester.widgetList<BotAvatar>(find.byType(BotAvatar)).toList();
    expect(avatars, isNotEmpty);
    expect(avatars.every((avatar) => avatar.animate), isTrue);
  });
}
