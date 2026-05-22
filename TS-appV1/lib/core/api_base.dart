/// Ghép URL gọi API `/api/v1/...` từ [origin] (không chứa `/api/v1`).
/// Ví dụ origin = `https://ts-server.fly.dev` → `https://ts-server.fly.dev/api/v1/repair-orders`.
String joinApiV1(String origin, String path) {
  final o = origin.trim().replaceAll(RegExp(r'/+$'), '');
  var p = path.trim();
  if (p.startsWith('/api/v1')) {
    p = p.substring('/api/v1'.length);
  }
  if (!p.startsWith('/')) p = '/$p';
  if (o.endsWith('/api/v1')) {
    return '$o$p';
  }
  return '$o/api/v1$p';
}
