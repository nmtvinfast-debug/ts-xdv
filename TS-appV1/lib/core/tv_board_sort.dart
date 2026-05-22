import 'package:flutter/material.dart';

import '../models/auth_models.dart';
import 'constants.dart';
import 'ro_display.dart';

/// Nhóm ưu tiên hiển thị trên bảng TV (số nhỏ = lên trên).
enum TvPriorityBand {
  urgent(0),
  active(1),
  waiting(2),
  nearComplete(3),
  other(4);

  const TvPriorityBand(this.sortOrder);
  final int sortOrder;
}

/// P1…P5 — màu viền / nhãn trên TV.
enum TvPriorityTier {
  p1Critical,
  p2Risk,
  p3Watch,
  p4Normal,
  p5Done,
}

extension TvPriorityTierStyle on TvPriorityTier {
  Color get color {
    switch (this) {
      case TvPriorityTier.p1Critical:
        return AppColors.statusDanger;
      case TvPriorityTier.p2Risk:
        return const Color(0xFFF97316);
      case TvPriorityTier.p3Watch:
        return AppColors.statusWarning;
      case TvPriorityTier.p4Normal:
        return AppColors.statusNormal;
      case TvPriorityTier.p5Done:
        return const Color(0xFF94A3B8);
    }
  }

  String get label {
    switch (this) {
      case TvPriorityTier.p1Critical:
        return 'P1';
      case TvPriorityTier.p2Risk:
        return 'P2';
      case TvPriorityTier.p3Watch:
        return 'P3';
      case TvPriorityTier.p4Normal:
        return 'P4';
      case TvPriorityTier.p5Done:
        return 'P5';
    }
  }
}

class TvBoardRank {
  final WorkOrderItem order;
  final TvPriorityBand band;
  final TvPriorityTier tier;
  final int priorityScore;
  final int slaOverdueMinutes;
  final int waitMinutes;

  const TvBoardRank({
    required this.order,
    required this.band,
    required this.tier,
    required this.priorityScore,
    required this.slaOverdueMinutes,
    required this.waitMinutes,
  });
}

int tvWaitMinutes(WorkOrderItem o) => o.minutesInState ?? 0;

int? _slaLimitMinutes(String status) {
  switch (normalizeRepairOrderStatus(status)) {
    case 'CHO_BAO_GIA':
      return SlaRules.timeToQuote;
    case 'CHO_PHAN_CONG':
      return SlaRules.timeToAssign;
    case 'CHO_SUA_CHUA':
      return SlaRules.timeToStartRepair;
    case 'CHO_QUYET_TOAN':
      return SlaRules.timeToSettle;
    case 'DA_THANH_TOAN':
    case 'KT_DUYET_RA_CONG':
      return SlaRules.timeToExit;
    default:
      return null;
  }
}

int tvSlaOverdueMinutes(WorkOrderItem o) {
  final limit = _slaLimitMinutes(o.status);
  if (limit == null) return 0;
  final w = tvWaitMinutes(o);
  return w > limit ? w - limit : 0;
}

bool _isNearComplete(String s) {
  return s == 'CHO_QUYET_TOAN' || s == 'DA_THANH_TOAN' || s == 'KT_DUYET_RA_CONG';
}

bool _isActiveWork(String s) {
  return s == 'DANG_SUA' || s == 'CHO_QD_KIEM_TRA' || s == 'DA_SUA_XONG';
}

TvPriorityBand tvClassifyBand(WorkOrderItem o) {
  final s = normalizeRepairOrderStatus(o.status);
  final overdue = tvSlaOverdueMinutes(o);
  final wait = tvWaitMinutes(o);

  if (_isNearComplete(s)) return TvPriorityBand.nearComplete;

  if (overdue > 0) return TvPriorityBand.urgent;
  if (s == 'CHO_PHAN_CONG' && o.ktvUsername.trim().isEmpty) return TvPriorityBand.urgent;
  if (s == 'CHO_KH_DUYET' && wait >= 30) return TvPriorityBand.urgent;
  if ((s == 'DUNG_SUA' || s == 'CHO_PHU_TUNG') && wait >= 60) return TvPriorityBand.urgent;
  if (s == 'DUNG_SUA' && wait >= 30) return TvPriorityBand.urgent;
  if (s == 'HUY_CHO_QUYET_TOAN' && wait >= 45) return TvPriorityBand.urgent;

  if (_isActiveWork(s)) return TvPriorityBand.active;

  if (s == 'CHO_KH_DUYET' ||
      s == 'CHO_PHU_TUNG' ||
      s == 'DUNG_SUA' ||
      s == 'CHO_BAO_GIA' ||
      s == 'CHO_CVDV_CHOT' ||
      s == 'CHO_SUA_CHUA' ||
      s == 'CHO_PHAN_CONG' ||
      s == 'XE_VAO_XUONG' ||
      s == 'HUY_CHO_QUYET_TOAN') {
    return TvPriorityBand.waiting;
  }

  return TvPriorityBand.other;
}

int tvPriorityScore(WorkOrderItem o) {
  final s = normalizeRepairOrderStatus(o.status);
  final overdue = tvSlaOverdueMinutes(o);
  final wait = tvWaitMinutes(o);
  var score = 0;

  if (overdue > 0) score += 100 + overdue.clamp(0, 120);
  if (s == 'DUNG_SUA') score += 80;
  if (s == 'CHO_PHU_TUNG') score += 60;
  if (s == 'CHO_KH_DUYET' && wait >= 30) score += 70;
  if (s == 'CHO_PHAN_CONG' && o.ktvUsername.trim().isEmpty) score += 75;
  if (s == 'DANG_SUA') score += 20;
  if (o.customerWaiting) score += 25;
  if (_isNearComplete(s)) score -= 50;

  return score;
}

TvPriorityTier tvPriorityTier(WorkOrderItem o) {
  final band = tvClassifyBand(o);
  final overdue = tvSlaOverdueMinutes(o);
  final wait = tvWaitMinutes(o);
  final s = normalizeRepairOrderStatus(o.status);
  final limit = _slaLimitMinutes(o.status);

  if (band == TvPriorityBand.nearComplete) return TvPriorityTier.p5Done;
  if (band == TvPriorityBand.urgent || overdue > 0) return TvPriorityTier.p1Critical;

  if (band == TvPriorityBand.active) return TvPriorityTier.p4Normal;

  if (s == 'DUNG_SUA' || s == 'CHO_PHU_TUNG' || (limit != null && wait >= limit)) {
    return TvPriorityTier.p2Risk;
  }
  if (band == TvPriorityBand.waiting && wait >= 20) return TvPriorityTier.p3Watch;

  return TvPriorityTier.p4Normal;
}

TvBoardRank tvRankOrder(WorkOrderItem o) {
  return TvBoardRank(
    order: o,
    band: tvClassifyBand(o),
    tier: tvPriorityTier(o),
    priorityScore: tvPriorityScore(o),
    slaOverdueMinutes: tvSlaOverdueMinutes(o),
    waitMinutes: tvWaitMinutes(o),
  );
}

int _compareTimeIn(WorkOrderItem a, WorkOrderItem b) {
  final ta = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  final tb = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  return ta.compareTo(tb);
}

/// Sắp xếp danh sách xe cho bảng TV (priority band → key trong nhóm).
void sortTvBoardOrders(List<WorkOrderItem> list) {
  list.sort((a, b) {
    final ra = tvRankOrder(a);
    final rb = tvRankOrder(b);

    final bandCmp = ra.band.sortOrder.compareTo(rb.band.sortOrder);
    if (bandCmp != 0) return bandCmp;

    switch (ra.band) {
      case TvPriorityBand.urgent:
        final od = rb.slaOverdueMinutes.compareTo(ra.slaOverdueMinutes);
        if (od != 0) return od;
        return rb.priorityScore.compareTo(ra.priorityScore);

      case TvPriorityBand.active:
        return _compareTimeIn(a, b);

      case TvPriorityBand.waiting:
        final w = rb.waitMinutes.compareTo(ra.waitMinutes);
        if (w != 0) return w;
        return rb.priorityScore.compareTo(ra.priorityScore);

      case TvPriorityBand.nearComplete:
        final st = _nearCompleteStatusOrder(a.status).compareTo(_nearCompleteStatusOrder(b.status));
        if (st != 0) return st;
        return rb.waitMinutes.compareTo(ra.waitMinutes);

      case TvPriorityBand.other:
        return rb.priorityScore.compareTo(ra.priorityScore);
    }
  });
}

int _nearCompleteStatusOrder(String status) {
  switch (normalizeRepairOrderStatus(status)) {
    case 'DA_THANH_TOAN':
      return 0;
    case 'KT_DUYET_RA_CONG':
      return 1;
    case 'CHO_QUYET_TOAN':
      return 2;
    default:
      return 9;
  }
}

List<WorkOrderItem> filterTvBoardSearch(List<WorkOrderItem> list, String query) {
  final q = query.trim().toLowerCase().replaceAll(RegExp(r'[\s\-]'), '');
  if (q.isEmpty) return list;
  return list.where((o) {
    final plate = o.bienSo.toLowerCase().replaceAll(RegExp(r'[\s\-]'), '');
    final ro = o.roCode.toLowerCase();
    final cvdv = o.cvdvUsername.toLowerCase();
    final ktv = o.ktvUsername.toLowerCase();
    final pos = o.position.toLowerCase();
    final note = o.customerNote.toLowerCase();
    final act = o.vehicleActivityNote.toLowerCase();
    return plate.contains(q) ||
        ro.contains(q) ||
        cvdv.contains(q) ||
        ktv.contains(q) ||
        pos.contains(q) ||
        note.contains(q) ||
        act.contains(q);
  }).toList();
}
