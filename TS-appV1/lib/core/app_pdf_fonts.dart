import 'package:pdf/widgets.dart' as pw;

/// Font PDF nhúng sẵn (gói `pdf`) — không cần plugin native `printing`/pdfium.
class AppPdfFonts {
  static final pw.Font regular = pw.Font.helvetica();
  static final pw.Font bold = pw.Font.helveticaBold();
}
