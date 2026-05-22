import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../core/platform_key.dart';
import '../core/workshop_features.dart';

bool get khAdmobPlatformSupported => isMobileNative;

/// Banner AdMob trên màn Khách hàng (chỉ Android/iOS).
class KhAdmobBanner extends StatefulWidget {
  final AdmobConfig config;

  const KhAdmobBanner({super.key, required this.config});

  @override
  State<KhAdmobBanner> createState() => _KhAdmobBannerState();
}

class _KhAdmobBannerState extends State<KhAdmobBanner> {
  BannerAd? _banner;
  bool _loaded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (khAdmobPlatformSupported) {
      _initAd();
    }
  }

  Future<void> _initAd() async {
    try {
      await MobileAds.instance.initialize();
      final unitId = defaultTargetPlatform == TargetPlatform.android
          ? widget.config.androidBannerUnitId
          : widget.config.iosBannerUnitId;
      final ad = BannerAd(
        adUnitId: unitId,
        size: AdSize.banner,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            if (mounted) setState(() => _loaded = true);
          },
          onAdFailedToLoad: (ad, err) {
            ad.dispose();
            if (mounted) {
              setState(() {
                _error = err.message;
                _loaded = false;
              });
            }
          },
        ),
      );
      await ad.load();
      if (!mounted) {
        ad.dispose();
        return;
      }
      setState(() => _banner = ad);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    _banner?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!khAdmobPlatformSupported) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Card(
          color: Colors.blueGrey.shade50,
          child: const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'AdMob chỉ hiển thị trên app Android/iOS. Trên Windows/Web hãy dùng chế độ Banner hoặc tắt QC.',
              style: TextStyle(fontSize: 13),
            ),
          ),
        ),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text('Không tải được quảng cáo AdMob: $_error', style: TextStyle(color: Colors.red.shade700, fontSize: 12)),
      );
    }

    if (_banner == null || !_loaded) {
      return const SizedBox(
        height: 60,
        child: Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Row(
            children: [
              Icon(Icons.ads_click, color: Colors.green.shade700, size: 20),
              const SizedBox(width: 8),
              const Text('Quảng cáo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('AdMob', style: TextStyle(fontSize: 11, color: Colors.green.shade900)),
              ),
            ],
          ),
        ),
        Center(
          child: SizedBox(
            width: _banner!.size.width.toDouble(),
            height: _banner!.size.height.toDouble(),
            child: AdWidget(ad: _banner!),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
