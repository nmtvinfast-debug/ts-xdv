import 'package:flutter/material.dart';
import 'numbered/parser.dart';
import 'screens/viewer.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    const demo = '''
# title: Thiên Niên Duyên (demo)
# key: Dm
# tempo: 72
# time: 4/4

| 5. 6. 1' 6. | 5. 3. 2. - |
| 1. 2. 3. 5. | 6. - 5. - |
| #5 6 5 3 | 2 - - - |
''';

    final song = parseNumberedSong(demo);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: NumberedViewerScreen(song: song),
    );
  }
}
