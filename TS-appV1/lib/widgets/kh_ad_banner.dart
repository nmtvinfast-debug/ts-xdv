import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/workshop_features.dart';
import '../models/auth_models.dart';
import '../services/api_service.dart';

/// Banner quảng cáo nội bộ trên màn Khách hàng (doanh thu khi KH xem).
class KhAdBanner extends StatefulWidget {
  final LoginResult login;
  final List<KhAdItem> ads;

  const KhAdBanner({super.key, required this.login, required this.ads});

  @override
  State<KhAdBanner> createState() => _KhAdBannerState();
}

class _KhAdBannerState extends State<KhAdBanner> {
  late final ApiService _api;
  late final PageController _pageCtrl;
  Timer? _auto;
  int _index = 0;
  final Set<String> _loggedViews = {};

  @override
  void initState() {
    super.initState();
    _api = ApiService(baseUrl: widget.login.baseUrl);
    _pageCtrl = PageController();
    if (widget.ads.length > 1) {
      _auto = Timer.periodic(const Duration(seconds: 8), (_) {
        if (!mounted || !_pageCtrl.hasClients) return;
        final next = (_index + 1) % widget.ads.length;
        _pageCtrl.animateToPage(next, duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _logView(0));
  }

  @override
  void dispose() {
    _auto?.cancel();
    _pageCtrl.dispose();
    super.dispose();
  }

  Future<void> _logView(int i) async {
    if (i < 0 || i >= widget.ads.length) return;
    final id = widget.ads[i].id;
    if (id.isEmpty || _loggedViews.contains(id)) return;
    _loggedViews.add(id);
    try {
      await _api.recordKhAdImpression(widget.login.token, id);
    } catch (_) {}
  }

  Future<void> _logClick(KhAdItem ad) async {
    if (ad.id.isEmpty) return;
    try {
      await _api.recordKhAdClick(widget.login.token, ad.id);
    } catch (_) {}
  }

  Future<void> _openLink(KhAdItem ad) async {
    await _logClick(ad);
    final url = ad.linkUrl.trim();
    if (url.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Quảng cáo: ${ad.title} — liên hệ xưởng để biết thêm.'),
            backgroundColor: Colors.indigo,
          ),
        );
      }
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Widget _bannerContent(KhAdItem ad) {
    final imgUrl = resolveKhAdImageUrl(widget.login.baseUrl, ad.imageUrl);
    if (imgUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              imgUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _gradientCard(ad),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black.withOpacity(0.75), Colors.transparent],
                  ),
                ),
                child: Text(
                  ad.title,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return _gradientCard(ad);
  }

  Widget _gradientCard(KhAdItem ad) {
    return Ink(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          colors: [Colors.indigo.shade700, Colors.blue.shade600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.local_offer, color: Colors.amber.shade300, size: 40),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    ad.title,
                    style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (ad.subtitle.isNotEmpty)
                    Text(
                      ad.subtitle,
                      style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 13),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white70),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.ads.isEmpty) return const SizedBox.shrink();

    final hasImage = widget.ads.any((a) => resolveKhAdImageUrl(widget.login.baseUrl, a.imageUrl).isNotEmpty);
    final height = hasImage ? 140.0 : 120.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Row(
            children: [
              Icon(Icons.campaign, color: Colors.amber.shade800, size: 20),
              const SizedBox(width: 8),
              const Text('Ưu đãi & đối tác', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('Quảng cáo', style: TextStyle(fontSize: 11, color: Colors.amber.shade900)),
              ),
            ],
          ),
        ),
        SizedBox(
          height: height,
          child: PageView.builder(
            controller: _pageCtrl,
            itemCount: widget.ads.length,
            onPageChanged: (i) {
              setState(() => _index = i);
              _logView(i);
            },
            itemBuilder: (_, i) {
              final ad = widget.ads[i];
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _openLink(ad),
                  borderRadius: BorderRadius.circular(14),
                  child: _bannerContent(ad),
                ),
              );
            },
          ),
        ),
        if (widget.ads.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                widget.ads.length,
                (i) => Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == _index ? Colors.blue : Colors.grey.shade400,
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 12),
      ],
    );
  }
}
