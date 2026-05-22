import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/workshop_features.dart';
import '../services/api_service.dart';

/// Cấu hình QC màn KH: tắt / Banner / AdMob + quản lý banner.
class AdminKhAdsPanel extends StatefulWidget {
  final ApiService api;
  final String token;
  final KhAdsMode mode;
  final ValueChanged<KhAdsMode> onModeChanged;
  final List<KhAdItem> ads;
  final ValueChanged<List<KhAdItem>> onAdsChanged;
  final TextEditingController androidBannerCtrl;
  final TextEditingController iosBannerCtrl;
  final bool saving;

  const AdminKhAdsPanel({
    super.key,
    required this.api,
    required this.token,
    required this.mode,
    required this.onModeChanged,
    required this.ads,
    required this.onAdsChanged,
    required this.androidBannerCtrl,
    required this.iosBannerCtrl,
    required this.saving,
  });

  @override
  State<AdminKhAdsPanel> createState() => _AdminKhAdsPanelState();
}

class _AdminKhAdsPanelState extends State<AdminKhAdsPanel> {
  bool _uploading = false;

  void _setAds(List<KhAdItem> next) => widget.onAdsChanged(next);

  Future<void> _pickAndUploadImage(int index) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final f = picked.files.first;
    final bytes = f.bytes;
    if (bytes == null || bytes.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không đọc được file ảnh.'), backgroundColor: Colors.red),
        );
      }
      return;
    }
    setState(() => _uploading = true);
    try {
      final url = await widget.api.uploadKhAdBannerImage(
        token: widget.token,
        imageBytes: bytes,
        filename: f.name.isNotEmpty ? f.name : 'banner.jpg',
      );
      final list = List<KhAdItem>.from(widget.ads);
      list[index] = list[index].copyWith(imageUrl: url);
      _setAds(list);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã tải ảnh banner lên server.'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload thất bại: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _addBanner() {
    final id = 'ad_${DateTime.now().millisecondsSinceEpoch}';
    _setAds([
      KhAdItem(id: id, title: 'Banner mới', subtitle: '', active: true),
      ...widget.ads,
    ]);
  }

  void _removeBanner(int index) {
    final list = List<KhAdItem>.from(widget.ads)..removeAt(index);
    _setAds(list);
  }

  void _editBanner(int index) {
    final ad = widget.ads[index];
    final titleCtrl = TextEditingController(text: ad.title);
    final subCtrl = TextEditingController(text: ad.subtitle);
    final linkCtrl = TextEditingController(text: ad.linkUrl);
    var active = ad.active;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Sửa banner'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(labelText: 'Tiêu đề *', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: subCtrl,
                    decoration: const InputDecoration(labelText: 'Mô tả ngắn', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: linkCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Link khi bấm (https://…)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  SwitchListTile(
                    title: const Text('Hiển thị'),
                    value: active,
                    onChanged: (v) => setDlg(() => active = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
            FilledButton(
              onPressed: () {
                final list = List<KhAdItem>.from(widget.ads);
                list[index] = ad.copyWith(
                  title: titleCtrl.text.trim().isEmpty ? ad.title : titleCtrl.text.trim(),
                  subtitle: subCtrl.text.trim(),
                  linkUrl: linkCtrl.text.trim(),
                  active: active,
                );
                _setAds(list);
                Navigator.pop(ctx);
              },
              child: const Text('Lưu'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Quảng cáo màn Khách hàng', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 4),
        Text(
          'Chọn một trong ba chế độ — chỉ một loại hiển thị trên app KH.',
          style: TextStyle(fontSize: 13, color: Colors.blueGrey.shade600),
        ),
        const SizedBox(height: 8),
        RadioListTile<KhAdsMode>(
          title: const Text('Tắt quảng cáo'),
          value: KhAdsMode.off,
          groupValue: widget.mode,
          onChanged: widget.saving ? null : (v) => widget.onModeChanged(v!),
        ),
        RadioListTile<KhAdsMode>(
          title: const Text('Banner nội bộ'),
          subtitle: const Text('Upload ảnh / carousel — ghi nhận lượt xem & click'),
          value: KhAdsMode.banner,
          groupValue: widget.mode,
          onChanged: widget.saving ? null : (v) => widget.onModeChanged(v!),
        ),
        RadioListTile<KhAdsMode>(
          title: const Text('Google AdMob'),
          subtitle: const Text('Banner AdMob tự động trên Android/iOS'),
          value: KhAdsMode.admob,
          groupValue: widget.mode,
          onChanged: widget.saving ? null : (v) => widget.onModeChanged(v!),
        ),
        if (widget.mode == KhAdsMode.banner) ...[
          const Divider(height: 24),
          Row(
            children: [
              const Expanded(
                child: Text('Danh sách banner', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
              TextButton.icon(
                onPressed: widget.saving || _uploading ? null : _addBanner,
                icon: const Icon(Icons.add),
                label: const Text('Thêm banner'),
              ),
            ],
          ),
          if (widget.ads.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('Chưa có banner — bấm «Thêm banner».', style: TextStyle(color: Colors.grey.shade600)),
            )
          else
            ...List.generate(widget.ads.length, (i) {
              final ad = widget.ads[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: ad.imageUrl.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.network(
                            resolveKhAdImageUrl(widget.api.baseUrl, ad.imageUrl),
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
                          ),
                        )
                      : const Icon(Icons.image_outlined, size: 40),
                  title: Text(ad.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    ad.subtitle.isEmpty ? (ad.active ? 'Đang bật' : 'Đã tắt') : ad.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'edit') _editBanner(i);
                      if (v == 'upload') _pickAndUploadImage(i);
                      if (v == 'delete') _removeBanner(i);
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'edit', child: Text('Sửa thông tin')),
                      PopupMenuItem(
                        value: 'upload',
                        enabled: !_uploading,
                        child: Text(_uploading ? 'Đang upload…' : 'Upload ảnh'),
                      ),
                      const PopupMenuItem(value: 'delete', child: Text('Xóa', style: TextStyle(color: Colors.red))),
                    ],
                  ),
                ),
              );
            }),
        ],
        if (widget.mode == KhAdsMode.admob) ...[
          const Divider(height: 24),
          const Text('AdMob — Banner Unit ID', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: widget.androidBannerCtrl,
            decoration: const InputDecoration(
              labelText: 'Android Banner Unit ID',
              hintText: 'ca-app-pub-xxx/yyy',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: widget.iosBannerCtrl,
            decoration: const InputDecoration(
              labelText: 'iOS Banner Unit ID',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Để trống sẽ dùng ID test Google. App ID cấu hình trong AndroidManifest / Info.plist.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
        ],
      ],
    );
  }
}
