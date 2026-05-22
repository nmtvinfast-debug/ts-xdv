import 'package:flutter/material.dart';
import '../numbered/song.dart';
import '../numbered/renderer.dart';

class NumberedViewerScreen extends StatefulWidget {
  final Song song;
  const NumberedViewerScreen({super.key, required this.song});

  @override
  State<NumberedViewerScreen> createState() => _NumberedViewerScreenState();
}

class _NumberedViewerScreenState extends State<NumberedViewerScreen> {
  double scale = 1.2;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.song.title)),
      body: LayoutBuilder(
        builder: (context, box) {
          // rough height estimate; ok for MVP
          final estimatedHeight = (widget.song.measures.length / 3.0).ceil() * 90.0 + 240.0;

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Row(
                  children: [
                    const Text("Zoom"),
                    Expanded(
                      child: Slider(
                        value: scale,
                        min: 0.8,
                        max: 2.2,
                        divisions: 14,
                        label: scale.toStringAsFixed(1),
                        onChanged: (v) => setState(() => scale = v),
                      ),
                    ),
                    SizedBox(width: 52, child: Text(scale.toStringAsFixed(1))),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ScrollConfiguration(
                  behavior: const ScrollBehavior().copyWith(scrollbars: true),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: CustomPaint(
                      size: Size(box.maxWidth, estimatedHeight),
                      painter: NumberedSheetPainter(
                        song: widget.song,
                        scale: scale,
                        lineWidth: box.maxWidth,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
