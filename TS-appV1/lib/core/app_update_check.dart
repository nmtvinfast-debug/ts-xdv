import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'constants.dart';
import 'platform_key.dart';

/// Kiểm tra máy chủ có bản mới (V2, V3…) và hiện dialog cập nhật.
class AppUpdateCheck {
  static bool _checkedThisSession = false;

  static Future<void> runIfNeeded(BuildContext context) async {
    if (_checkedThisSession) return;
    _checkedThisSession = true;
    try {
      final info = await PackageInfo.fromPlatform();
      final uri = Uri.parse('${AppConfig.serverOrigin}/api/v1/app/release').replace(
        queryParameters: {
          'version': info.version,
          'build': info.buildNumber,
          'platform': appReleasePlatformKey(),
        },
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200 || !context.mounted) return;

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['update_available'] != true) return;

      final label = data['version_label']?.toString() ?? 'mới';
      final message = data['message']?.toString().trim() ??
          'Đã có phiên bản mới $label! Bạn có muốn cập nhật không?';
      final url = data['download_url']?.toString().trim() ?? '';
      final mandatory = data['mandatory'] == true;

      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: !mandatory,
        builder: (ctx) => AlertDialog(
          title: const Text('Cập nhật phần mềm'),
          content: Text(message),
          actions: [
            if (!mandatory)
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Để sau'),
              ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                if (url.isEmpty) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Chưa cấu hình link tải bản mới trên máy chủ (Admin).'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                  }
                  return;
                }
                final link = Uri.parse(url);
                if (await canLaunchUrl(link)) {
                  await launchUrl(
                    link,
                    mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
                  );
                } else if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Không mở được link: $url'), backgroundColor: Colors.red),
                  );
                }
              },
              child: const Text('Cập nhật'),
            ),
          ],
        ),
      );
    } catch (_) {
      /* Mạng / server — bỏ qua, không chặn đăng nhập */
    }
  }
}
