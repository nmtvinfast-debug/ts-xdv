/**
 * SLA mặc định (phút) — theo Time Rules trong đặc tả nội bộ TS-XDV.
 * Có thể ghi đè qua bảng app_settings.workshop_defaults.
 */
export const DEFAULT_SLA_MINUTES = {
  quote_after_time_in: 30,
  customer_approval: 120,
  assign_after_quote_approved: 15,
  start_repair_after_assign: 30,
  settlement_after_time_done: 30,
  exit_after_paid: 15,
  parts_pause_warn: 120,
  customer_pause_remind: 60,
};

/** Đơn giá mặc định (VND) — Admin có thể sửa trong cấu hình. */
export const DEFAULT_KH_ADS_REVENUE = {
  vnd_per_view: 500,
  vnd_per_click: 3000,
};

export const DEFAULT_KH_ADS = [
  {
    id: 'promo_bd',
    title: 'Gói bảo dưỡng định kỳ',
    subtitle: 'Ưu đãi dầu nhớt & lọc — đặt lịch qua app',
    image_url: '',
    link_url: '',
    active: true,
  },
  {
    id: 'promo_pt',
    title: 'Phụ tùng chính hãng',
    subtitle: 'Cam kết nguồn gốc VinFast / GSM',
    image_url: '',
    link_url: '',
    active: true,
  },
];

export const DEFAULT_WORKSHOP_DEFAULTS = {
  sla_minutes: DEFAULT_SLA_MINUTES,
  timezone: 'Asia/Ho_Chi_Minh',
  company_name: 'TS-XDV AUTO SERVICE',
  features: {
    company_chat_enabled: true,
    kh_ads_enabled: true,
    kh_ads_mode: 'banner',
  },
  /** AdMob — Admin nhập unit ID thật; mặc định dùng ID test của Google. */
  admob: {
    android_app_id: 'ca-app-pub-3940256099942544~3347511713',
    ios_app_id: 'ca-app-pub-3940256099942544~1458002511',
    android_banner_unit_id: 'ca-app-pub-3940256099942544/6300978111',
    ios_banner_unit_id: 'ca-app-pub-3940256099942544/2934735716',
  },
  kh_ads_revenue: DEFAULT_KH_ADS_REVENUE,
  kh_ads: DEFAULT_KH_ADS,
  /** Phiên bản app — khi tăng build_number / version, app cũ hiện dialog cập nhật. */
  app_release: {
    version_label: 'V2.0',
    version: '2.0.0',
    build_number: 200,
    message: 'Bản V2: sửa Gọi CVDV cho khách hàng, đồng bộ dữ liệu xưởng. Vui lòng cập nhật.',
    download_url: '',
    /** App chạy trên trình duyệt — thư mục build/web deploy lên /releases/web/ */
    download_url_web: 'https://ts-server.fly.dev/releases/web/',
    download_url_windows: 'https://ts-server.fly.dev/releases/ts_xdv.exe',
    download_url_android: 'https://ts-server.fly.dev/releases/ts-xdv.apk',
    download_url_ios: '',
    mandatory: false,
  },
};
