enum CrossPlatformSaveOutcome { saved, shared, downloaded, cancelled, failed }

class CrossPlatformSaveResult {
  final CrossPlatformSaveOutcome outcome;
  final String? pathOrHint;

  const CrossPlatformSaveResult(this.outcome, [this.pathOrHint]);

  bool get ok =>
      outcome == CrossPlatformSaveOutcome.saved ||
      outcome == CrossPlatformSaveOutcome.shared ||
      outcome == CrossPlatformSaveOutcome.downloaded;

  String snackbarMessage(String fileName) {
    switch (outcome) {
      case CrossPlatformSaveOutcome.saved:
        return 'Đã lưu $fileName${pathOrHint != null ? ' → $pathOrHint' : ''}';
      case CrossPlatformSaveOutcome.shared:
        return 'Đã mở hộp thoại chia sẻ — chọn Lưu vào Tệp / Drive / Gmail…';
      case CrossPlatformSaveOutcome.downloaded:
        return 'Trình duyệt đang tải $fileName (kiểm tra thư mục Tải xuống)';
      case CrossPlatformSaveOutcome.cancelled:
        return 'Đã hủy lưu file.';
      case CrossPlatformSaveOutcome.failed:
        return pathOrHint ?? 'Không lưu được file.';
    }
  }
}
