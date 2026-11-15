// 字团：吉祥物的身体、配色、动作，五官位置换成名字的首个「字」。
//
// 用户定的「文字头像」就是这个：不再画旧圆圈首字母。首字按字素取
// （`characters`），组合 emoji 也算一个字；身体/颜色/动作沿用 [MascotSpec]。

import 'package:flutter/material.dart';

import 'mascot_avatar.dart';

class MascotLetterAvatar extends StatelessWidget {
  const MascotLetterAvatar({
    super.key,
    required this.spec,
    required this.letter,
    this.size = 40,
    this.animate = false,
    this.emotion,
  });

  /// 身体/颜色/动作从这套配置来（旧 Bot 由 `letterMascotOf` 按 id 派生）。
  final MascotSpec spec;

  /// 已经取好的首字素，如「芽」「J」「😀」「👨‍👩‍👧」。
  final String letter;

  final double size;
  final bool animate;

  /// 情绪只影响身体动作与特效，字不换。
  final String? emotion;

  @override
  Widget build(BuildContext context) => MascotAvatar(
    spec: spec,
    size: size,
    animate: animate,
    emotion: emotion,
    letter: letter,
  );
}
