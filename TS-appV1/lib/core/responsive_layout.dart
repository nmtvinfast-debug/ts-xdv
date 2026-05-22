import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Phân loại thiết bị / cửa sổ — dùng chung cho KH, đăng nhập, v.v.
enum AppFormFactor { phone, tablet, desktop }

AppFormFactor appFormFactor(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  final w = size.width;
  final shortest = size.shortestSide;

  if (kIsWeb) {
    if (w >= 1100) return AppFormFactor.desktop;
    if (w >= 640) return AppFormFactor.tablet;
    return AppFormFactor.phone;
  }

  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
      if (shortest < 520) return AppFormFactor.phone;
      if (shortest < 720) return AppFormFactor.tablet;
      return AppFormFactor.tablet;
    default:
      if (w >= 1000) return AppFormFactor.desktop;
      if (w >= 720) return AppFormFactor.tablet;
      return AppFormFactor.phone;
  }
}

/// Độ rộng nội dung tối đa (để không bị “ốm” trên web/màn hình lớn).
double appContentMaxWidth(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  switch (appFormFactor(context)) {
    case AppFormFactor.phone:
      return w;
    case AppFormFactor.tablet:
      return math.min(w - 28, 860);
    case AppFormFactor.desktop:
      if (kIsWeb) return math.min(w - 48, 1080);
      return math.min(w - 40, 960);
  }
}

/// Padding ngang cân giữa theo [appContentMaxWidth].
EdgeInsets appPageHorizontalPadding(BuildContext context, {double top = 12, double bottom = 12}) {
  final w = MediaQuery.sizeOf(context).width;
  final maxW = appContentMaxWidth(context);
  final side = w > maxW + 8 ? (w - maxW) / 2 : 12.0;
  return EdgeInsets.fromLTRB(side, top, side, bottom);
}

bool appIsPhone(BuildContext context) => appFormFactor(context) == AppFormFactor.phone;

/// Padding nội dung màn hình (mobile nhỏ hơn desktop).
EdgeInsets appScreenPadding(BuildContext context) {
  final f = appFormFactor(context);
  switch (f) {
    case AppFormFactor.phone:
      return const EdgeInsets.all(12);
    case AppFormFactor.tablet:
      return const EdgeInsets.all(16);
    case AppFormFactor.desktop:
      return const EdgeInsets.all(24);
  }
}

double appPanelTitleSize(BuildContext context, {double desktop = 20}) {
  switch (appFormFactor(context)) {
    case AppFormFactor.phone:
      return 15;
    case AppFormFactor.tablet:
      return 17;
    case AppFormFactor.desktop:
      return desktop;
  }
}
