import 'package:flutter/material.dart';
import 'song.dart';

class NumberedSheetPainter extends CustomPainter {
  final Song song;
  final double scale;
  final double lineWidth;

  NumberedSheetPainter({
    required this.song,
    required this.scale,
    required this.lineWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(scale);

    final paint = Paint()..isAntiAlias = true;

    const titleStyle = TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.black);
    const metaStyle = TextStyle(fontSize: 12, color: Colors.black87);
    const noteStyle = TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.black);
    const accStyle = TextStyle(fontSize: 14.4, fontWeight: FontWeight.w700, color: Colors.black);
    final dotPaint = Paint()..color = Colors.black;

    double x = 16;
    double y = 16;

    _drawText(canvas, song.title, Offset(x, y), titleStyle);
    y += 26;
    _drawText(canvas, "Key: ${song.key}   Tempo: ${song.tempo}   Time: ${song.timeSig}", Offset(x, y), metaStyle);
    y += 24;

    final usableWidth = (lineWidth / scale) - 32;
    const measureGap = 14.0;
    const lineGap = 34.0;
    final baseLineY = y + 16;

    double cursorX = x;
    double cursorY = baseLineY;

    for (final measure in song.measures) {
      final mw = _measureWidth(measure);
      if (cursorX + mw > x + usableWidth) {
        cursorX = x;
        cursorY += lineGap;
      }

      _drawBar(canvas, cursorX, cursorY - 12, cursorY + 12, paint);
      cursorX += 8;

      for (final t in measure.tokens) {
        if (t is SpacerToken) {
          cursorX += 10 * t.weight;
          continue;
        }

        if (t is RestToken) {
          final restTp = TextPainter(
            text: const TextSpan(text: "0", style: noteStyle),
            textDirection: TextDirection.ltr,
          )..layout();
          restTp.paint(canvas, Offset(cursorX, cursorY - restTp.height / 2));

          if (t.sustain > 0) {
            _drawSustain(canvas, cursorX + restTp.width + 4, cursorY + 12, t.sustain, paint);
            cursorX += restTp.width + 4 + t.sustain * 10;
          } else {
            cursorX += restTp.width + 10;
          }
          continue;
        }

        if (t is NoteToken) {
          double accW = 0;
          if (t.accidental != 0) {
            final accText = t.accidental == 1 ? "#" : "b";
            final tpAcc = TextPainter(
              text: TextSpan(text: accText, style: accStyle),
              textDirection: TextDirection.ltr,
            )..layout();
            tpAcc.paint(canvas, Offset(cursorX, cursorY - tpAcc.height / 2));
            accW = tpAcc.width + 2;
          }

          final tp = TextPainter(
            text: TextSpan(text: "${t.degree}", style: noteStyle),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(canvas, Offset(cursorX + accW, cursorY - tp.height / 2));

          final noteCenterX = cursorX + accW + tp.width / 2;

          // octave dots
          if (t.octave != 0) {
            final dotCount = t.octave.abs();
            final dy = t.octave > 0 ? -(tp.height / 2 + 6) : (tp.height / 2 + 6);
            for (int k = 0; k < dotCount; k++) {
              final oy = dy + (t.octave > 0 ? -6.0 * k : 6.0 * k);
              canvas.drawCircle(Offset(noteCenterX, cursorY + oy), 1.8, dotPaint);
            }
          }

          final w = accW + tp.width;
          if (t.sustain > 0) {
            _drawSustain(canvas, cursorX + w + 4, cursorY + 12, t.sustain, paint);
            cursorX += w + 4 + t.sustain * 10;
          } else {
            cursorX += w + 10;
          }
        }
      }

      _drawBar(canvas, cursorX, cursorY - 12, cursorY + 12, paint);
      cursorX += measureGap;
    }

    canvas.restore();
  }

  double _measureWidth(Measure m) {
    double w = 0;
    for (final t in m.tokens) {
      if (t is SpacerToken) {
        w += 10 * t.weight;
      } else if (t is RestToken) {
        w += 18 + (t.sustain * 10);
      } else if (t is NoteToken) {
        w += (t.accidental != 0 ? 10 : 0) + 18 + (t.sustain * 10);
      }
    }
    return w + 24;
  }

  void _drawBar(Canvas c, double x, double y1, double y2, Paint p) {
    c.drawLine(Offset(x, y1), Offset(x, y2), p..strokeWidth = 1.2);
  }

  void _drawSustain(Canvas c, double startX, double y, int count, Paint p) {
    final total = count * 10.0;
    c.drawLine(Offset(startX, y), Offset(startX + total, y), p..strokeWidth = 1.2);
  }

  void _drawText(Canvas c, String text, Offset pos, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, pos);
  }

  @override
  bool shouldRepaint(covariant NumberedSheetPainter oldDelegate) {
    return oldDelegate.song != song || oldDelegate.scale != scale || oldDelegate.lineWidth != lineWidth;
  }
}
