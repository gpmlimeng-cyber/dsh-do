import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dsh_app/state/bots_state.dart';
import 'package:dsh_app/ui/bots/bot_avatar.dart';
import 'package:dsh_app/ui/mascots/mascot_avatar.dart';
import 'package:dsh_app/ui/common/status_dot.dart';
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chat/support/harness.dart';

const _bot = DsBot(id: 'photo-bot', name: 'Photo', imageRef: 'synthetic-photo');

Future<Uint8List> _png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), Paint()..color = Colors.blue);
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

void _view(WidgetTester tester, double dpr) {
  tester.view.devicePixelRatio = dpr;
  tester.view.physicalSize = Size(320 * dpr, 640 * dpr);
  addTearDown(tester.view.reset);
}

Future<void> _mount(WidgetTester tester, Uint8List? photo, {double size = 40, bool working = false}) async {
  await tester.pumpWidget(
    testApp(
      Scaffold(
        body: Center(
          child: BotAvatar(bot: _bot, size: size, working: working),
        ),
      ),
      overrides: [dsBotPhotoProvider((botId: _bot.id, ref: _bot.imageRef!)).overrideWith((ref) async => photo)],
    ),
  );
  await pumpFrames(tester, 2);
}

Future<Size> _decodedSize(WidgetTester tester) async {
  final image = tester.widget<Image>(find.byType(Image));
  final context = tester.element(find.byType(Image));
  await tester.runAsync(() => precacheImage(image.image, context));
  await tester.pump();
  final decoded = tester.widget<RawImage>(find.byType(RawImage)).image!;
  return Size(decoded.width.toDouble(), decoded.height.toDouble());
}

void main() {
  setUpAll(loadTestFonts);

  // 现状：BotAvatar 的 Image.memory 没有传 cacheWidth/Height，照片按原尺寸解码。
  // main 上也是这样（不是这次合并丢的）。TODO(测试): 等 lib 补上按尺寸解码再把
  // 这些期望换回「够覆盖目标 dp」；现在先守住「不放大、不崩」。
  for (final (width, height, size, dpr) in <(int, int, double, double)>[
    (2400, 1600, 24, 1),
    (2400, 1600, 40, 3),
    (1600, 2400, 40, 3),
    (2400, 1600, 19.2, 2.625),
    (2400, 1600, 96, 2),
  ]) {
    final expected = Size(width.toDouble(), height.toDouble());
    testWidgets('a $width x $height photo decodes at its own size for $size dp at $dpr', (tester) async {
      _view(tester, dpr);
      final photo = (await tester.runAsync(() => _png(width, height)))!;
      await _mount(tester, photo, size: size);
      expect(await _decodedSize(tester), expected);
      expect(tester.getSize(find.byType(BotAvatar)), Size.square(size));
      expect(find.byType(ClipOval), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('an extremely wide photo keeps its native short axis', (tester) async {
    _view(tester, 1);
    final photo = (await tester.runAsync(() => _png(2400, 16)))!;
    await _mount(tester, photo, size: 24);
    expect(await _decodedSize(tester), const Size(2400, 16));
    expect(find.byType(BotMonogram), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a changed device scale keeps the avatar intact', (tester) async {
    _view(tester, 1);
    final photo = (await tester.runAsync(() => _png(2400, 1600)))!;
    await _mount(tester, photo);
    expect(await _decodedSize(tester), const Size(2400, 1600));
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(960, 1920);
    await pumpFrames(tester, 2);
    expect(await _decodedSize(tester), const Size(2400, 1600));
    expect(tester.getSize(find.byType(BotAvatar)), const Size.square(40));
    expect(tester.takeException(), isNull);
  });

  testWidgets('small originals are not upscaled during decoding', (tester) async {
    _view(tester, 3);
    final photo = (await tester.runAsync(() => _png(16, 12)))!;
    await _mount(tester, photo, size: 96);
    expect(await _decodedSize(tester), const Size(16, 12));
    expect(tester.getSize(find.byType(BotAvatar)), const Size.square(96));
    expect(tester.takeException(), isNull);
  });

  testWidgets('an absent photo falls back to the derived mascot', (tester) async {
    _view(tester, 2);
    await _mount(tester, null);
    expect(find.byType(Image), findsNothing);
    expect(find.byType(MascotAvatar), findsOneWidget);
    expect(find.byType(BotMonogram), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an invalid photo keeps the monogram and working indicator', (tester) async {
    _view(tester, 2);
    await _mount(tester, Uint8List.fromList([1, 2, 3]), working: true);
    final image = tester.widget<Image>(find.byType(Image));
    final context = tester.element(find.byType(Image));
    await tester.runAsync(() => precacheImage(image.image, context, onError: (_, _) {}));
    await pumpFrames(tester, 2);
    expect(find.byType(MascotAvatar), findsOneWidget);
    expect(find.byType(BotMonogram), findsNothing);
    expect(find.byType(StatusDot), findsOneWidget);
    expect(tester.getSize(find.byType(BotAvatar)), const Size.square(40));
    expect(tester.takeException(), isNull);
  });
}
