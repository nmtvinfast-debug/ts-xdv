// Đọc `workshop_defaults` từ API settings (features, kh_ads, admob, …).

enum KhAdsMode { off, banner, admob }

KhAdsMode parseKhAdsMode(dynamic raw, {bool? legacyEnabled}) {
  final s = raw?.toString().trim().toLowerCase();
  if (s == 'off') return KhAdsMode.off;
  if (s == 'banner') return KhAdsMode.banner;
  if (s == 'admob') return KhAdsMode.admob;
  if (legacyEnabled == false) return KhAdsMode.off;
  return KhAdsMode.banner;
}

String khAdsModeToApi(KhAdsMode mode) {
  switch (mode) {
    case KhAdsMode.off:
      return 'off';
    case KhAdsMode.banner:
      return 'banner';
    case KhAdsMode.admob:
      return 'admob';
  }
}

class WorkshopFeatures {
  final bool companyChatEnabled;
  final KhAdsMode khAdsMode;
  final KhAdsRevenue khAdsRevenue;
  final List<KhAdItem> khAds;
  final AdmobConfig admob;
  final Map<String, dynamic> raw;

  const WorkshopFeatures({
    required this.companyChatEnabled,
    required this.khAdsMode,
    required this.khAdsRevenue,
    required this.khAds,
    required this.admob,
    required this.raw,
  });

  bool get khAdsEnabled => khAdsMode == KhAdsMode.banner;

  bool get khAdmobEnabled => khAdsMode == KhAdsMode.admob;

  static WorkshopFeatures fromSettingsResponse(Map<String, dynamic> json) {
    final wd = json['workshop_defaults'];
    final map = wd is Map<String, dynamic>
        ? wd
        : (wd is Map ? Map<String, dynamic>.from(wd) : <String, dynamic>{});
    final features = map['features'];
    final f = features is Map<String, dynamic>
        ? features
        : (features is Map ? Map<String, dynamic>.from(features) : <String, dynamic>{});

    bool flag(dynamic v, {bool defaultValue = true}) {
      if (v is bool) return v;
      if (v is String) return v.toLowerCase() == 'true' || v == '1';
      return defaultValue;
    }

    final legacyEnabled = f['kh_ads_enabled'];
    final legacyBool = legacyEnabled is bool
        ? legacyEnabled
        : (legacyEnabled is String ? legacyEnabled.toLowerCase() == 'true' : null);

    final adsRaw = map['kh_ads'];
    final ads = <KhAdItem>[];
    if (adsRaw is List) {
      for (final e in adsRaw) {
        if (e is Map) {
          final item = KhAdItem.fromJson(Map<String, dynamic>.from(e));
          if (item.active) ads.add(item);
        }
      }
    }

    return WorkshopFeatures(
      companyChatEnabled: flag(f['company_chat_enabled'], defaultValue: true),
      khAdsMode: parseKhAdsMode(f['kh_ads_mode'], legacyEnabled: legacyBool),
      khAdsRevenue: KhAdsRevenue.fromJson(map['kh_ads_revenue']),
      khAds: ads,
      admob: AdmobConfig.fromJson(map['admob']),
      raw: map,
    );
  }
}

/// Đơn giá doanh thu quảng cáo banner (VND / lượt).
class KhAdsRevenue {
  final double vndPerView;
  final double vndPerClick;

  const KhAdsRevenue({required this.vndPerView, required this.vndPerClick});

  factory KhAdsRevenue.fromJson(dynamic json) {
    final m = json is Map<String, dynamic>
        ? json
        : (json is Map ? Map<String, dynamic>.from(json) : <String, dynamic>{});
    double numVal(dynamic v, double fallback) {
      final n = double.tryParse(v?.toString() ?? '');
      if (n == null || n.isNaN || n < 0) return fallback;
      return n;
    }

    return KhAdsRevenue(
      vndPerView: numVal(m['vnd_per_view'], 500),
      vndPerClick: numVal(m['vnd_per_click'], 3000),
    );
  }

  Map<String, dynamic> toJson() => {
        'vnd_per_view': vndPerView,
        'vnd_per_click': vndPerClick,
      };
}

class AdmobConfig {
  final String androidAppId;
  final String iosAppId;
  final String androidBannerUnitId;
  final String iosBannerUnitId;

  const AdmobConfig({
    required this.androidAppId,
    required this.iosAppId,
    required this.androidBannerUnitId,
    required this.iosBannerUnitId,
  });

  static const testAndroidBanner = 'ca-app-pub-3940256099942544/6300978111';
  static const testIosBanner = 'ca-app-pub-3940256099942544/2934735716';

  factory AdmobConfig.fromJson(dynamic json) {
    final m = json is Map<String, dynamic>
        ? json
        : (json is Map ? Map<String, dynamic>.from(json) : <String, dynamic>{});
    String pick(List<String> keys, String fallback) {
      for (final k in keys) {
        final v = m[k]?.toString().trim();
        if (v != null && v.isNotEmpty) return v;
      }
      return fallback;
    }

    return AdmobConfig(
      androidAppId: pick(['android_app_id'], 'ca-app-pub-3940256099942544~3347511713'),
      iosAppId: pick(['ios_app_id'], 'ca-app-pub-3940256099942544~1458002511'),
      androidBannerUnitId: pick(['android_banner_unit_id'], testAndroidBanner),
      iosBannerUnitId: pick(['ios_banner_unit_id'], testIosBanner),
    );
  }

  Map<String, dynamic> toJson() => {
        'android_app_id': androidAppId,
        'ios_app_id': iosAppId,
        'android_banner_unit_id': androidBannerUnitId,
        'ios_banner_unit_id': iosBannerUnitId,
      };
}

class KhAdItem {
  final String id;
  final String title;
  final String subtitle;
  final String imageUrl;
  final String linkUrl;
  final bool active;

  const KhAdItem({
    required this.id,
    this.title = '',
    this.subtitle = '',
    this.imageUrl = '',
    this.linkUrl = '',
    this.active = true,
  });

  factory KhAdItem.fromJson(Map<String, dynamic> json) {
    return KhAdItem(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      subtitle: json['subtitle']?.toString() ?? '',
      imageUrl: json['image_url']?.toString() ?? '',
      linkUrl: json['link_url']?.toString() ?? '',
      active: json['active'] != false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'subtitle': subtitle,
        'image_url': imageUrl,
        'link_url': linkUrl,
        'active': active,
      };

  KhAdItem copyWith({
    String? id,
    String? title,
    String? subtitle,
    String? imageUrl,
    String? linkUrl,
    bool? active,
  }) {
    return KhAdItem(
      id: id ?? this.id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      imageUrl: imageUrl ?? this.imageUrl,
      linkUrl: linkUrl ?? this.linkUrl,
      active: active ?? this.active,
    );
  }
}

/// URL ảnh banner (tương đối `/uploads/...` hoặc tuyệt đối).
String resolveKhAdImageUrl(String apiBaseUrl, String imageUrl) {
  final u = imageUrl.trim();
  if (u.isEmpty) return '';
  if (u.startsWith('http://') || u.startsWith('https://')) return u;
  final base = apiBaseUrl.replaceAll(RegExp(r'/$'), '');
  return u.startsWith('/') ? '$base$u' : '$base/$u';
}
