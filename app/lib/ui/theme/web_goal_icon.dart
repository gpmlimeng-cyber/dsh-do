// 网页端目标胶囊第一行那颗靶心（ds-bot `src/client/icons.js:127` 的 `GoalIcon`，
// 用在 `header.js:130` 的 `.bt-pill-ico` 里）。图标字体里没有它：那段是手写的
// 描边路径，不是 Phosphor 字形，所以按同一段 SVG 原样画一遍——viewBox 20、
// stroke 1.5、圆端圆角，坐标一个不改，只按 size/20 缩放。
//
// 四条路径：
//   M15.1 8.8A6.5 6.5 0 1 1 11.2 4.9   外圈（右上方留给箭头，缺约 50°）
//   M9 8a3 3 0 1 0 0 6 3 3 0 1 0 0-6   内圈（圆心 9,11、半径 3）
//   M9 11l7.5-7.5                       箭头杆
//   M14.6 2.8v2.6h2.6                   箭头两侧的折角

import 'package:flutter/material.dart';

/// 网页端那颗「目标」靶心，按 [size] 缩放，颜色取 [color]。
class WebGoalIcon extends StatelessWidget {
  const WebGoalIcon({super.key, required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _WebGoalPainter(color)),
  );
}

class _WebGoalPainter extends CustomPainter {
  const _WebGoalPainter(this.color);

  final Color color;

  /// 网页 SVG 的 viewBox 边长。
  static const _box = 20.0;

  /// 两个圈共用的圆心。
  static const _center = Offset(9, 11);

  /// 外圈起点角（度）：`M15.1 8.8` 在圆心右侧略上。
  static const _startAngle = -19.8;

  /// 顺时针画到 `11.2 4.9`：右下绕一整圈，右上留出箭头那道缺口。
  static const _sweep = 309.6;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.shortestSide / _box;
    if (k <= 0) return;
    canvas.save();
    canvas.scale(k);
    // 墨迹在 viewBox 里从 x≈1.75 起（外圈 center(9,11)、r6.5、stroke1.5），
    // 盒子左边这一截是空的：平移过去，靶心可见的左边缘就落在盒子左边缘，
    // 和胶囊第二行那颗圆点同一根线（两行左对齐）。
    canvas.translate(-1.75, 0);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    canvas.drawArc(
      Rect.fromCircle(center: _center, radius: 6.5),
      _startAngle * (3.141592653589793 / 180),
      _sweep * (3.141592653589793 / 180),
      false,
      paint,
    );
    canvas.drawCircle(_center, 3, paint);
    canvas.drawLine(_center, const Offset(16.5, 3.5), paint);
    canvas.drawPath(
      Path()
        ..moveTo(14.6, 2.8)
        ..lineTo(14.6, 5.4)
        ..lineTo(17.2, 5.4),
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WebGoalPainter old) => old.color != color;
}
