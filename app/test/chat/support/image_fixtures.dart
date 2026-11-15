// Scripted DS Bot answers for the shared image bubble: a host that counts
// images but sends no refs (an older host, and the placeholder path), and one
// that sends `imageRefs` plus the `image` endpoint that serves the bytes.

import '../../bots/support.dart';

/// The base64 payload the `image` endpoint returns, taken from the tiny PNG the
/// Bot pages' fixtures already carry.
String get tinyPngBase64 => tinyPhoto.substring(tinyPhoto.indexOf(',') + 1);

Map<String, Object?> imageRef(String attachmentId, {String? mime = 'image/png', String? name = 'photo.png'}) => {
  'attachmentId': attachmentId,
  'mime': mime,
  'name': name,
};

/// An older host: the message carries only the count, so the bubble keeps the
/// 「［图片］」 placeholder.
FakeDsBotTransport imageCountOnlyTransport() {
  final transport = FakeDsBotTransport();
  final time = todayAt(14, 0).millisecondsSinceEpoch;
  transport.chatItems = <Object?>[
    {'kind': 'user', 'text': '', 'time': time, 'images': 2},
  ];
  return transport;
}

/// A host that advertises `images` (and, by default, `image-preview`) and sends
/// `imageRefs`; the `image` endpoint answers with one tiny PNG.
FakeDsBotTransport imageCapableTransport({List<Map<String, Object?>>? refs, bool previewCapability = true}) {
  final transport = FakeDsBotTransport();
  final time = todayAt(14, 0).millisecondsSinceEpoch;
  transport.chatItems = <Object?>[
    {
      'kind': 'user',
      'text': '',
      'time': time,
      'images': (refs ?? [imageRef('att-1')]).length,
      'imageRefs': refs ?? [imageRef('att-1')],
    },
  ];
  transport.handlers['hello'] = (_) => {
    ...transport.helloAnswer(),
    'capabilities': ['state', 'chat', 'send', 'images', if (previewCapability) 'image-preview'],
  };
  transport.handlers['image'] = (_) => {'mime': 'image/png', 'data': tinyPngBase64};
  return transport;
}
