/**
 * Cấu hình phiên bản app desktop/mobile — so sánh với client để nhắc cập nhật V2, V3…
 */
export const DEFAULT_APP_RELEASE = {
  /** Nhãn hiển thị: "V2.0", "V3.0"… */
  version_label: 'V1.0',
  /** Semver máy chủ (mới hơn app cũ → bật dialog) */
  version: '1.0.0',
  /** Số build tăng dần: V1=1, V2=200, V3=300… */
  build_number: 1,
  message: '',
  download_url: '',
  download_url_web: '',
  download_url_windows: '',
  download_url_android: '',
  download_url_ios: '',
  /** Bắt buộc cập nhật — không có nút «Để sau» */
  mandatory: false,
};

export function parseVersionParts(v) {
  const s = String(v || '0.0.0').trim();
  const m = s.match(/^(\d+)(?:\.(\d+))?(?:\.(\d+))?/);
  return [
    parseInt(m?.[1] ?? '0', 10),
    parseInt(m?.[2] ?? '0', 10),
    parseInt(m?.[3] ?? '0', 10),
  ];
}

export function compareVersion(a, b) {
  const pa = parseVersionParts(a);
  const pb = parseVersionParts(b);
  for (let i = 0; i < 3; i++) {
    if (pa[i] !== pb[i]) return pa[i] > pb[i] ? 1 : -1;
  }
  return 0;
}

export function mergeAppRelease(stored) {
  const base = { ...DEFAULT_APP_RELEASE };
  if (!stored || typeof stored !== 'object') return base;
  return {
    ...base,
    ...stored,
    version_label: String(stored.version_label ?? base.version_label).trim() || base.version_label,
    version: String(stored.version ?? base.version).trim() || base.version,
    build_number: Number(stored.build_number) || base.build_number,
    mandatory: stored.mandatory === true,
  };
}

/** Client gửi ?platform=web|windows|android|ios */
export function pickDownloadUrl(release, platform) {
  const p = String(platform || '').toLowerCase();
  if (p === 'web' && release.download_url_web) return release.download_url_web;
  if (p === 'windows' && release.download_url_windows) return release.download_url_windows;
  if (p === 'android' && release.download_url_android) return release.download_url_android;
  if ((p === 'ios' || p === 'iphone') && release.download_url_ios) return release.download_url_ios;
  return (
    release.download_url_web ||
    release.download_url_windows ||
    release.download_url_android ||
    release.download_url ||
    ''
  );
}

export function isUpdateAvailable(clientVersion, clientBuild, release) {
  const build = Number(clientBuild) || 0;
  const serverBuild = Number(release.build_number) || 0;
  if (serverBuild > build) return true;
  return compareVersion(release.version, clientVersion) > 0;
}
