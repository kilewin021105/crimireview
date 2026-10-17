import 'package:flutter/material.dart';

/// The Google "G" mark for the sign-in button, drawn from Google's own
/// vector shapes (SVG path data) so it stays crisp at any size without
/// image files or a network download.
///
/// Brand rule followed: the G keeps its four colours and is never
/// recoloured.
class GoogleLogo extends StatelessWidget {
  final double size;
  const GoogleLogo({super.key, this.size = 20});

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.square(size),
        painter: _SvgPainter(viewBox: 48, layers: const [
          (0xFFEA4335, 'M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 '
              '14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z'),
          (0xFF4285F4, 'M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 '
              '5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z'),
          (0xFFFBBC05, 'M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 '
              '16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z'),
          (0xFF34A853, 'M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 '
              '2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z'),
        ]),
      );
}

class _SvgPainter extends CustomPainter {
  final double viewBox;
  final List<(int, String)> layers;

  _SvgPainter({required this.viewBox, required this.layers});

  static final Map<String, Path> _cache = {};

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / viewBox, size.height / viewBox);
    final paint = Paint()..isAntiAlias = true;
    for (final (color, data) in layers) {
      paint.color = Color(color);
      canvas.drawPath(_cache.putIfAbsent(data, () => parseSvgPath(data)), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SvgPainter old) => old.layers != layers || old.viewBox != viewBox;
}

/// Converts SVG path data (the `d` attribute) into a Flutter [Path].
/// Supports the commands the logo above uses: M L H V C S Z, in absolute
/// (upper case) and relative (lower case) form, with repeated arguments.
Path parseSvgPath(String data) {
  final tokens = RegExp(r'[MmLlHhVvCcSsZz]|-?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?')
      .allMatches(data)
      .map((m) => m.group(0)!)
      .toList();
  final path = Path();
  var i = 0;
  var cmd = '';
  double x = 0, y = 0, startX = 0, startY = 0;
  double? lastCtrlX, lastCtrlY;

  bool isCommand(String t) => RegExp(r'^[A-Za-z]$').hasMatch(t);
  double next() => double.parse(tokens[i++]);

  while (i < tokens.length) {
    if (isCommand(tokens[i])) cmd = tokens[i++];
    final rel = cmd == cmd.toLowerCase();
    final dx = rel ? x : 0.0, dy = rel ? y : 0.0;
    switch (cmd.toUpperCase()) {
      case 'M':
        x = dx + next();
        y = dy + next();
        path.moveTo(x, y);
        startX = x;
        startY = y;
        // Extra pairs after a move are line-tos.
        cmd = rel ? 'l' : 'L';
        lastCtrlX = null;
      case 'L':
        x = dx + next();
        y = dy + next();
        path.lineTo(x, y);
        lastCtrlX = null;
      case 'H':
        x = dx + next();
        path.lineTo(x, y);
        lastCtrlX = null;
      case 'V':
        y = dy + next();
        path.lineTo(x, y);
        lastCtrlX = null;
      case 'C':
        final x1 = dx + next(), y1 = dy + next();
        final x2 = dx + next(), y2 = dy + next();
        x = dx + next();
        y = dy + next();
        path.cubicTo(x1, y1, x2, y2, x, y);
        lastCtrlX = x2;
        lastCtrlY = y2;
      case 'S':
        // First control point mirrors the previous curve's second one.
        final x1 = lastCtrlX == null ? x : 2 * x - lastCtrlX;
        final y1 = lastCtrlY == null || lastCtrlX == null ? y : 2 * y - lastCtrlY;
        final x2 = dx + next(), y2 = dy + next();
        x = dx + next();
        y = dy + next();
        path.cubicTo(x1, y1, x2, y2, x, y);
        lastCtrlX = x2;
        lastCtrlY = y2;
      case 'Z':
        path.close();
        x = startX;
        y = startY;
        lastCtrlX = null;
        cmd = ''; // Z takes no arguments; a stray number is skipped below.
      default:
        i++; // Unknown token: skip rather than loop forever.
    }
  }
  return path;
}
