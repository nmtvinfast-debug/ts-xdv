class Song {
  final String title;
  final String key; // e.g. Dm, Em, C
  final int tempo; // bpm
  final String timeSig; // e.g. 4/4
  final List<Measure> measures;

  const Song({
    required this.title,
    required this.key,
    required this.tempo,
    required this.timeSig,
    required this.measures,
  });
}

class Measure {
  final List<Token> tokens;
  const Measure(this.tokens);
}

/// Token types for numbered notation
sealed class Token {
  const Token();
}

class NoteToken extends Token {
  final int degree; // 1..7
  final int octave; // -2..+2 (dot below => -1, dot above => +1)
  final int accidental; // -1 (b), 0, +1 (#)
  final int sustain; // number of trailing '-' after this note/rest
  const NoteToken({
    required this.degree,
    required this.octave,
    required this.accidental,
    required this.sustain,
  });
}

class RestToken extends Token {
  final int sustain;
  const RestToken({required this.sustain});
}

class SpacerToken extends Token {
  /// visual spacing weight
  final double weight;
  const SpacerToken({this.weight = 1.0});
}
