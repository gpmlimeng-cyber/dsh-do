// 界面: which home the app opens to (原生 / 网页), then everything about the
// web app — opening it once, its phone layout, and the display and sending
// preferences the official General settings keep on the host's engine (only
// the web app reads them; they were 通用设置).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/engine_settings_state.dart';
import '../../state/im_mode_state.dart';
import '../../state/quick_panel_state.dart';
import '../../state/settings_state.dart';
import '../../state/table_tint_state.dart';
import '../../state/ui_mode_state.dart';
import '../common/app_sheet.dart';
import '../common/sheet_title_bar.dart';
import '../engine_settings/namespace_copy.dart';
import '../engine_settings/schema_form.dart';
import '../shell/page_frame.dart';
import '../shell/quick_panel.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';
import '../web/local_web_screen.dart';
import 'im_face_strings.dart';
import 'quick_panel_items_sheet.dart';
import 'settings_widgets.dart';

SchemaFieldSpec _field(String ns, String key) => SchemaFieldSpec(ns, [key], copy: copyOf(ns, [key]));

/// 聊天界面: 专业 (the home that has always been there) or 轻松 (the IM shell,
/// lib/ui/im/). A one-time card explains it the first time; the light home has
/// no web counterpart, so a switch out of 网页模式 comes with the change.
Future<void> chooseInterfaceFace(BuildContext context, WidgetRef ref, InterfaceMode mode) async {
  if (mode == ref.read(interfaceModeProvider).mode) return;
  final notifier = ref.read(interfaceModeProvider.notifier);
  if (mode == InterfaceMode.light) {
    if (!await notifier.introSeen()) {
      if (!context.mounted) return;
      final confirmed = await _showImIntro(context);
      await notifier.markIntroSeen();
      if (!confirmed || !context.mounted) return;
    }
    if (ref.read(uiModeProvider).web) {
      await ref.read(uiModeProvider.notifier).set(UiMode.native);
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(ImFaceStrings.lightNativeOnly)),
      );
    }
  }
  await notifier.set(mode);
  if (!context.mounted) return;
  // The home is under this page: closing the stack lands on the new one.
  Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
}

Future<bool> _showImIntro(BuildContext context) async {
  final confirmed = await showAppSheet<bool>(
    context,
    builder: (sheet) => SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetTitleBar(ImFaceStrings.introTitle),
          Padding(
            padding: const EdgeInsets.fromLTRB(kSheetGutter, 0, kSheetGutter, 8),
            child: Text(
              ImFaceStrings.introBody,
              style: Theme.of(sheet).textTheme.bodyMedium?.copyWith(color: Theme.of(sheet).colorScheme.onSurfaceVariant),
            ),
          ),
          SheetGroup(
            children: [
              ListTile(
                leading: const Icon(AppIcons.done),
                title: Text(ImFaceStrings.introStart),
                onTap: () => Navigator.pop(sheet, true),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ),
    ),
  );
  return confirmed == true;
}

String _faceLabel(InterfaceMode mode) => switch (mode) {
  InterfaceMode.pro => ImFaceStrings.pro,
  InterfaceMode.light => ImFaceStrings.light,
};

class InterfacePage extends ConsumerWidget {
  const InterfacePage({super.key});

  /// The web app's settings on the host's engine.
  static const namespaces = ['ui-settings', 'ui-chat', 'ui-conversation'];

  /// The new home takes over from the bottom of the stack (this page closes
  /// with the rest; the way back is the new home).
  static void choose(BuildContext context, WidgetRef ref, UiMode mode) {
    if (mode == ref.read(uiModeProvider).mode) return;
    Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
    unawaited(ref.read(uiModeProvider.notifier).set(mode));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final mode = ref.watch(uiModeProvider.select((s) => s.mode));
    final face = ref.watch(interfaceModeProvider.select((s) => s.mode));
    final settings = ref.watch(settingsProvider);
    final tableTint = ref.watch(tableTintProvider);
    final engine = ref.watch(engineSettingsProvider).value;
    final quickPanel = ref.watch(quickPanelProvider);
    return AppPage.list(
      title: l10n.hubSettingsInterface,
      children: [
        SettingsSection(
          title: ImFaceStrings.faceTitle,
          spot: Spots.uiMode,
          children: [
            for (final option in InterfaceMode.values)
              Semantics(
                checked: option == face,
                inMutuallyExclusiveGroup: true,
                child: SettingsTile(
                  key: ValueKey('interface-face-${option.name}'),
                  title: _faceLabel(option),
                  subtitle: option == InterfaceMode.light ? ImFaceStrings.lightHint : null,
                  trailing: SizedBox.square(
                    dimension: 32,
                    child: Icon(option == face ? AppIcons.radioOn : AppIcons.radioOff, size: 24),
                  ),
                  onTap: () => unawaited(chooseInterfaceFace(context, ref, option)),
                ),
              ),
          ],
        ),
        SettingsSection(
          title: l10n.hubInterfaceHome,
          spot: Spots.uiMode,
          // 轻松模式 draws no web home: the choice stays stored, but the rows
          // wait until 专业模式 is back.
          footer: face == InterfaceMode.light ? Text(ImFaceStrings.lightNativeOnly) : null,
          children: [
            for (final m in UiMode.values)
              Semantics(
                checked: m == mode,
                inMutuallyExclusiveGroup: true,
                child: SettingsTile(
                  key: ValueKey('ui-mode-${m.name}'),
                  title: m.label,
                  subtitle: m == UiMode.web ? l10n.hubInterfaceWebHint : null,
                  trailing: SizedBox.square(
                    dimension: 32,
                    child: Icon(m == mode ? AppIcons.radioOn : AppIcons.radioOff, size: 24),
                  ),
                  onTap: face == InterfaceMode.light ? null : () => choose(context, ref, m),
                ),
              ),
          ],
        ),
        SettingsSection(
          title: l10n.commonWeb,
          spot: Spots.webApp,
          children: [
            SettingsTile(
              spot: Spots.openWeb,
              // In 网页模式 the web app is the home underneath.
              onTap: () => mode == UiMode.web
                  ? Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst)
                  : Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const LocalWebScreen())),
            ),
            SettingsSwitchTile(
              spot: Spots.webPhoneLayout,
              subtitle: l10n.hubSettingsWebPhoneLayoutHint,
              value: settings.webPhoneLayout,
              onChanged: (v) => unawaited(ref.read(settingsProvider.notifier).setWebPhoneLayout(v)),
            ),
          ],
        ),
        SettingsSection(
          title: l10n.hubSettingsChat,
          children: [
            SettingsSwitchTile(
              spot: Spots.hardwareEnterSends,
              subtitle: l10n.hubHardwareEnterSendsHint,
              value: settings.hardwareEnterSends,
              onChanged: (v) => unawaited(ref.read(settingsProvider.notifier).setHardwareEnterSends(v)),
            ),
          ],
        ),
        SettingsSection(
          title: l10n.hubQuickPanel,
          spot: Spots.quickPanel,
          children: [
            SettingsSwitchTile(
              key: const ValueKey('quick-panel-swipe'),
              title: l10n.hubQuickPanelSwipe,
              subtitle: l10n.hubQuickPanelSwipeHint,
              value: quickPanel.swipe,
              onChanged: (v) => unawaited(ref.read(quickPanelProvider.notifier).setSwipe(v)),
            ),
            SettingsTile(
              key: const ValueKey('quick-panel-items'),
              title: l10n.hubQuickPanelItems,
              subtitle: quickPanel.items.isEmpty
                  ? l10n.hubQuickPanelItemsNone
                  : quickPanel.items.map((d) => d.label(l10n)).join(l10n.shellListSeparator),
              onTap: () => unawaited(showQuickPanelItems(context)),
            ),
          ],
        ),
        SettingsSection(
          title: l10n.hubTableTint,
          spot: Spots.tableTint,
          children: [
            for (final tint in TableTint.values)
              Semantics(
                checked: tint == tableTint,
                inMutuallyExclusiveGroup: true,
                child: SettingsTile(
                  key: ValueKey('table-tint-${tint.name}'),
                  title: switch (tint) {
                    TableTint.follow => l10n.hubTableTintFollow,
                    TableTint.fill => l10n.hubTableTintFill,
                    TableTint.none => l10n.hubTableTintNone,
                  },
                  subtitle: switch (tint) {
                    TableTint.follow => l10n.hubTableTintFollowHint,
                    TableTint.fill => l10n.hubTableTintFillHint,
                    TableTint.none => l10n.hubTableTintNoneHint,
                  },
                  // 一眼看出这一档长什么样：缩略图和正文表格同一套配色。
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _TableTintPreview(tint: tint, selected: tint == tableTint),
                      const SizedBox(width: 10),
                      Icon(
                        tint == tableTint ? AppIcons.radioOn : AppIcons.radioOff,
                        size: 24,
                        color: tint == tableTint ? Theme.of(context).colorScheme.primary : null,
                      ),
                    ],
                  ),
                  onTap: () => unawaited(ref.read(tableTintProvider.notifier).set(tint)),
                ),
              ),
          ],
        ),
        // The host's own: only once it has said what it keeps.
        if (engine != null && namespaces.any(engine.served))
          ...schemaFormGroups([
            SchemaFormSection(
              title: l10n.engineGeneralWebDisplay,
              fields: [
                _field('ui-settings', 'enabled'),
                _field('ui-chat', 'transcriptView'),
                _field('ui-chat', 'collapseTiming'),
                _field('ui-chat', 'performanceUsage'),
              ],
            ),
            SchemaFormSection(
              title: l10n.engineGeneralWebSending,
              fields: [_field('ui-conversation', 'busyEnter'), _field('ui-chat', 'linkOpening')],
            ),
          ], settings: engine),
      ],
    );
  }
}

/// 表格底色每档的迷你示意：两列三行，表头一档、隔行一档，和正文表格
/// 用同一套颜色，深浅主题都对得上。
class _TableTintPreview extends StatelessWidget {
  const _TableTintPreview({required this.tint, required this.selected});

  final TableTint tint;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dsh = DshColors.of(context);
    return SizedBox(
      width: 58,
      height: 38,
      child: CustomPaint(
        painter: _TableTintPainter(
          header: tint == TableTint.none ? null : dsh.codeWellHeader,
          stripe: tint == TableTint.fill ? colors.onSurface.withValues(alpha: 0.05) : null,
          line: colors.outlineVariant,
          border: selected ? colors.primary : colors.outlineVariant,
          borderWidth: selected ? 1.4 : 0.8,
        ),
      ),
    );
  }
}

class _TableTintPainter extends CustomPainter {
  const _TableTintPainter({
    required this.header,
    required this.stripe,
    required this.line,
    required this.border,
    required this.borderWidth,
  });

  final Color? header;
  final Color? stripe;
  final Color line;
  final Color border;
  final double borderWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final row = size.height / 3;
    final outline = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(5));

    // 填充和网格都裁进圆角里，和修好之后的正文表格一个规矩。
    canvas.save();
    canvas.clipRRect(outline);
    final fill = Paint();
    if (header != null) {
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, row), fill..color = header!);
    }
    if (stripe != null) {
      canvas.drawRect(Rect.fromLTWH(0, row * 2, size.width, row), fill..color = stripe!);
    }
    final grid = Paint()
      ..color = line
      ..strokeWidth = 0.7
      ..style = PaintingStyle.stroke;
    canvas.drawPath(
      Path()
        ..moveTo(size.width / 2, 0)
        ..lineTo(size.width / 2, size.height)
        ..moveTo(0, row)
        ..lineTo(size.width, row)
        ..moveTo(0, row * 2)
        ..lineTo(size.width, row * 2),
      grid,
    );
    canvas.restore();

    canvas.drawRRect(
      outline,
      Paint()
        ..color = border
        ..strokeWidth = borderWidth
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_TableTintPainter old) =>
      old.header != header ||
      old.stripe != stripe ||
      old.line != line ||
      old.border != border ||
      old.borderWidth != borderWidth;
}
