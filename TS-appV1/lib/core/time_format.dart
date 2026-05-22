/// Định dạng thời gian chờ dạng **ngày, giờ, phút** (tiếng Việt), không dùng "8000 phút".
String formatDurationVnFromMinutes(int totalMinutes) {
  if (totalMinutes < 0) totalMinutes = 0;
  final days = totalMinutes ~/ (24 * 60);
  var rem = totalMinutes % (24 * 60);
  final hours = rem ~/ 60;
  final mins = rem % 60;
  final parts = <String>[];
  if (days > 0) parts.add('$days ngày');
  if (hours > 0) parts.add('$hours giờ');
  if (mins > 0 || parts.isEmpty) parts.add('$mins phút');
  return parts.join(', ');
}

String formatDurationVnFromDuration(Duration d) {
  final m = d.inMinutes;
  return formatDurationVnFromMinutes(m < 0 ? 0 : m);
}

/// Khoảng thời gian từ [created] đến hiện tại.
String formatWaitSinceDateTime(DateTime? created, {String ifNull = 'Chưa rõ'}) {
  if (created == null) return ifNull;
  return formatDurationVnFromDuration(DateTime.now().difference(created));
}
