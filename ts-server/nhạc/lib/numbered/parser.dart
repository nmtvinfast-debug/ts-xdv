import 'song.dart';

Song parseNumberedSong(String input) {
  String title = "Untitled";
  String key = "C";
  int tempo = 72;
  String timeSig = "4/4";

  final measures = <Measure>[];

  final lines = input.split('\n');
  final buffer = StringBuffer();
  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty) continue;

    if (line.startsWith('#')) {
      final s = line.substring(1).trim();
      if (s.toLowerCase().startsWith('title:')) {
        title = s.substring(6).trim();
      } else if (s.toLowerCase().startsWith('key:')) {
        key = s.substring(4).trim();
      } else if (s.toLowerCase().startsWith('tempo:')) {
        tempo = int.tryParse(s.substring(6).trim()) ?? tempo;
      } else if (s.toLowerCase().startsWith('time:')) {
        timeSig = s.substring(5).trim();
      }
      continue;
    }

    buffer.writeln(line);
  }

  final text = buffer.toString();

  // Find segments between bars | ... |
  final barRegex = RegExp(r'\|([^|]+)\|');
  final matches = barRegex.allMatches(text).toList();
  for (final m in matches) {
    final inside = m.group(1) ?? '';
    measures.add(Measure(_tokenizeMeasure(inside)));
  }

  // If user didn't put bars, treat whole content as one measure
  if (measures.isEmpty) {
    measures.add(Measure(_tokenizeMeasure(text)));
  }

  return Song(title: title, key: key, tempo: tempo, timeSig: timeSig, measures: measures);
}

List<Token> _tokenizeMeasure(String s) {
  final parts = s
      .replaceAll('\t', ' ')
      .split(RegExp(r'\s+'))
      .where((e) => e.trim().isNotEmpty)
      .toList();

  final out = <Token>[];

  for (int i = 0; i < parts.length; i++) {
    final p = parts[i].trim();

    // sustain-only tokens like "-" or "--"
    if (RegExp(r'^-+$').hasMatch(p)) {
      final count = p.length;
      if (out.isNotEmpty) {
        final last = out.last;
        if (last is NoteToken) {
          out[out.length - 1] = NoteToken(
            degree: last.degree,
            octave: last.octave,
            accidental: last.accidental,
            sustain: last.sustain + count,
          );
          continue;
        } else if (last is RestToken) {
          out[out.length - 1] = RestToken(sustain: last.sustain + count);
          continue;
        }
      }
      out.add(SpacerToken(weight: count.toDouble()));
      continue;
    }

    // Parse accidental prefix
    int accidental = 0;
    String body = p;
    if (body.startsWith('#')) {
      accidental = 1;
      body = body.substring(1);
    } else if (body.startsWith('b')) {
      accidental = -1;
      body = body.substring(1);
    }

    // Parse core + marks ('.' lowers, ''' raises)
    final markRegex = RegExp(r"^([0-7rR])([.'']*)$");
    final mm = markRegex.firstMatch(body);
    if (mm == null) {
      out.add(const SpacerToken(weight: 1.0));
      continue;
    }

    final core = mm.group(1) ?? '';
    final marks = mm.group(2) ?? '';

    int octave = 0;
    for (final ch in marks.split('')) {
      if (ch == '.') octave -= 1;
      if (ch == "'") octave += 1;
    }
    if (octave < -2) octave = -2;
    if (octave > 2) octave = 2;

    if (core == '0' || core.toLowerCase() == 'r') {
      out.add(const RestToken(sustain: 0));
    } else {
      final degree = int.tryParse(core) ?? 1;
      out.add(NoteToken(degree: degree, octave: octave, accidental: accidental, sustain: 0));
    }

    // small spacing between tokens
    out.add(const SpacerToken(weight: 0.6));
  }

  if (out.isNotEmpty && out.last is SpacerToken) out.removeLast();
  return out;
}
