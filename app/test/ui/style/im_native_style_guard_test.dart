// 轻松模式（IM）与吉祥物界面的「原生风格」守卫：不另造一套视觉，只走 App 的组件与代币。
//
// 扫 `lib/ui/im/` 与 `lib/ui/mascots/`：
//   - 颜色：不许写十六进制色值，用 `theme.colorScheme` / `DshColors`
//     （例外：`mascot_avatar.dart` 是吉祥物画布，渐变和阴影必须写色值）
//   - 圆角：不许写数字字面量半径，用 `AppShape`
//     （按比例算的半径如 `Radius.circular(r.width * 0.1)` 不算违规）
//   - 图标：`Icons.*` 已由 `test/icons/app_icons_test.dart` 全仓拦截，这里不重复
//
// 生成文件（`*.g.dart`）跳过，和 `tool/l10n_scan.py` 的口径一致。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 这两个目录里的界面必须符合 App 原生风格。
const _scanned = ['lib/ui/im', 'lib/ui/mascots'];

/// 吉祥物渲染内部允许写色值：它是画出来的图形，不是界面皮肤。
const _paintFiles = {'lib/ui/mascots/mascot_avatar.dart'};

/// 命中：行号（从 1 开始）与整行原文，报错时直接能定位。
class StyleHit {
  const StyleHit(this.line, this.text);
  final int line;
  final String text;
}

bool _isIdentCode(int code) =>
    code >= 0x30 && code <= 0x39 || // 0-9
    code >= 0x41 && code <= 0x5A || // A-Z
    code >= 0x61 && code <= 0x7A || // a-z
    code == 0x5F || code == 0x24; // _ $

/// 把注释和字符串字面量涂掉，只留可执行代码，避免文案里出现 `Color(0x` 这类误报。
String _codeOnly(String source) {
  final out = StringBuffer();
  var i = 0;
  while (i < source.length) {
    final c = source[i];
    final next = i + 1 < source.length ? source[i + 1] : '';
    if (c == '/' && next == '/') {
      while (i < source.length && source[i] != '\n') {
        i++;
      }
      continue;
    }
    if (c == '/' && next == '*') {
      i += 2;
      while (i < source.length) {
        if (source[i] == '*' && i + 1 < source.length && source[i + 1] == '/') {
          i += 2;
          break;
        }
        // 保留换行，行号才不会错位。
        if (source[i] == '\n') out.write('\n');
        i++;
      }
      continue;
    }
    if (c == "'" || c == '"') {
      final quote = c;
      final triple = i + 2 < source.length && source[i + 1] == quote && source[i + 2] == quote;
      // r'...' 是原始字符串，里面的反斜杠不是转义。
      final raw = !triple && i > 0 && source[i - 1] == 'r' && (i - 2 < 0 || !_isIdentCode(source.codeUnitAt(i - 2)));
      i += triple ? 3 : 1;
      while (i < source.length) {
        if (!raw && source[i] == r'\') {
          i += 2;
          continue;
        }
        if (triple) {
          if (source[i] == quote &&
              i + 2 < source.length &&
              source[i + 1] == quote &&
              source[i + 2] == quote) {
            i += 3;
            break;
          }
        } else if (source[i] == quote) {
          i += 1;
          break;
        }
        if (source[i] == '\n') out.write('\n');
        i++;
      }
      out.write(' '); // 占个位，别把左右两段代码粘在一起
      continue;
    }
    out.write(c);
    i++;
  }
  return out.toString();
}

/// 在可执行代码里找 `pattern` 的命中位置。
///
/// [identBoundary] 为真时，要求命中点前面不是标识符字符——用来把
/// `FooColor(0x...)` 这类自定义类排除在界面色值之外。圆角规则关掉它，
/// 这样 `BorderRadius.circular(24)` 和 `Radius.circular(24)` 一样被当作裸半径。
List<StyleHit> _scan(String source, RegExp pattern, {bool identBoundary = true}) {
  final code = _codeOnly(source);
  final sourceLines = source.split('\n');
  final hits = <StyleHit>[];
  for (final match in pattern.allMatches(code)) {
    if (identBoundary && match.start > 0 && _isIdentCode(code.codeUnitAt(match.start - 1))) {
      continue;
    }
    final line = '\n'.allMatches(code.substring(0, match.start)).length + 1;
    final text = line <= sourceLines.length ? sourceLines[line - 1].trim() : '';
    hits.add(StyleHit(line, text));
  }
  return hits;
}

/// 十六进制色值：`Color(0xFF112233)`。
List<StyleHit> hexColorHits(String source) =>
    _scan(source, RegExp(r'Color\(\s*0x[0-9a-fA-F]'));

/// 数字字面量半径：`Radius.circular(8)`、`BorderRadius.circular(24)`。
/// 只认纯数字参数，`Radius.circular(r.width * 0.1)` 这类按比例算的不算。
List<StyleHit> numericRadiusHits(String source) => _scan(
      source,
      RegExp(r'Radius\.circular\(\s*[0-9]+(?:\.[0-9]+)?\s*\)'),
      identBoundary: false,
    );

/// 两个目录下所有手写 Dart 文件（跳过生成文件），路径统一成 `/` 分隔。
List<String> _sources() {
  final files = <String>[];
  for (final dir in _scanned) {
    for (final entity in Directory(dir).listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      if (path.endsWith('.g.dart')) continue;
      files.add(path);
    }
  }
  files.sort();
  return files;
}

void main() {
  group('守卫规则本身', () {
    test('注释和字符串里的色值不算违规', () {
      expect(hexColorHits('// 旧写法 Color(0xFF112233)\n'), isEmpty);
      expect(hexColorHits("const hint = 'Color(0xFF112233)';\n"), isEmpty);
      expect(hexColorHits('/* Color(0xFF112233) */\n'), isEmpty);
    });

    test('代码里的色值要命中，且行号正确', () {
      final hits = hexColorHits('final a = 1;\nfinal c = Color(0xFF112233);\n');
      expect(hits, hasLength(1));
      expect(hits.single.line, 2);
    });

    test('按比例算的半径放行，数字字面量半径要命中', () {
      expect(numericRadiusHits('Radius.circular(r.width * 0.1)\n'), isEmpty);
      expect(numericRadiusHits('Radius.circular(AppShape.md)\n'), isEmpty);
      expect(numericRadiusHits('Radius.circular(4.5 * u)\n'), isEmpty);
      expect(numericRadiusHits('Radius.circular(8)\n'), hasLength(1));
      expect(numericRadiusHits('BorderRadius.circular(24.0)\n'), hasLength(1));
    });
  });

  test('扫描范围不为空（防止目录改名后守卫空转）', () {
    final files = _sources();
    expect(files.length, greaterThan(10));
    expect(files.any((p) => p.startsWith('lib/ui/im/')), isTrue);
    expect(files.any((p) => p.startsWith('lib/ui/mascots/')), isTrue);
  });

  test('轻松模式与吉祥物界面不写十六进制色值', () {
    final offenders = <String>[];
    for (final path in _sources()) {
      if (_paintFiles.contains(path)) continue;
      final source = File(path).readAsStringSync();
      offenders.addAll(hexColorHits(source).map((h) => '$path:${h.line}: ${h.text}'));
    }
    expect(
      offenders,
      isEmpty,
      reason: '界面颜色只用 theme.colorScheme / DshColors；吉祥物渲染（${_paintFiles.join(', ')}）除外。',
    );
  });

  test('轻松模式与吉祥物界面不写数字圆角', () {
    final offenders = <String>[];
    for (final path in _sources()) {
      final source = File(path).readAsStringSync();
      offenders.addAll(numericRadiusHits(source).map((h) => '$path:${h.line}: ${h.text}'));
    }
    expect(
      offenders,
      isEmpty,
      reason: '圆角只用 AppShape（lib/ui/theme/shapes.dart），不写裸的 Radius.circular(数字)。',
    );
  });
}
