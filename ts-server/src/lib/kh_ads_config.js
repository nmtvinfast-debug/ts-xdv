import { DEFAULT_WORKSHOP_DEFAULTS } from './default_sla.js';

/** Gộp cấu hình xưởng với mặc định (dùng khi ghi nhận QC / thống kê). */
export function mergeWorkshopDefaults(stored) {
  const prev = stored && typeof stored === 'object' ? stored : {};
  const next = { ...DEFAULT_WORKSHOP_DEFAULTS, ...prev };
  next.features = { ...DEFAULT_WORKSHOP_DEFAULTS.features, ...(prev.features || {}) };
  next.kh_ads_revenue = {
    ...DEFAULT_WORKSHOP_DEFAULTS.kh_ads_revenue,
    ...(prev.kh_ads_revenue || {}),
  };
  next.kh_ads = Array.isArray(prev.kh_ads) ? prev.kh_ads : DEFAULT_WORKSHOP_DEFAULTS.kh_ads;
  next.admob = { ...DEFAULT_WORKSHOP_DEFAULTS.admob, ...(prev.admob || {}) };
  const mode = resolveKhAdsMode(next);
  next.features.kh_ads_mode = mode;
  next.features.kh_ads_enabled = mode === 'banner';
  return next;
}

export const KH_ADS_MODES = ['off', 'banner', 'admob'];

/** off | banner | admob — tương thích kh_ads_enabled cũ. */
export function resolveKhAdsMode(merged) {
  const raw = String(merged?.features?.kh_ads_mode ?? '')
    .trim()
    .toLowerCase();
  if (KH_ADS_MODES.includes(raw)) return raw;
  if (merged?.features?.kh_ads_enabled === false) return 'off';
  return 'banner';
}

export function khAdsBannerMode(merged) {
  return resolveKhAdsMode(merged) === 'banner';
}

export function khAdsAdmobMode(merged) {
  return resolveKhAdsMode(merged) === 'admob';
}

/** Banner nội bộ (lượt xem/click) — không áp dụng AdMob. */
export function khAdsEnabled(merged) {
  return khAdsBannerMode(merged);
}

function toNonNegNumber(v, fallback = 0) {
  const n = Number(v);
  if (!Number.isFinite(n) || n < 0) return fallback;
  return Math.round(n * 100) / 100;
}

/** Đơn giá VND/lượt — ưu tiên theo từng banner, không có thì dùng mặc định chung. */
export function resolveKhAdRates(adId, merged) {
  const global = merged?.kh_ads_revenue || {};
  const gView = toNonNegNumber(global.vnd_per_view, 0);
  const gClick = toNonNegNumber(global.vnd_per_click, 0);
  const ads = Array.isArray(merged?.kh_ads) ? merged.kh_ads : [];
  const ad = ads.find((a) => a && String(a.id) === String(adId));
  return {
    vndPerView: ad?.vnd_per_view != null ? toNonNegNumber(ad.vnd_per_view, gView) : gView,
    vndPerClick: ad?.vnd_per_click != null ? toNonNegNumber(ad.vnd_per_click, gClick) : gClick,
  };
}
