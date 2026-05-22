import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/cross_platform_export_helpers.dart' show exportActionLabel, saveCsvExport, showCrossPlatformSaveSnackBar;
import '../core/responsive_layout.dart';
import '../core/ke_toan_debt_types.dart';
import '../core/ke_toan_tracking_store.dart';
import '../core/payment_info.dart';
import '../models/kt_tracking_entry.dart';
import 'column_filter_menu_header.dart';
import 'ke_toan_debt_classify_dialog.dart';

/// Tab «Theo dõi»: bảng cột + lọc tam giác (giống Kho) · Chưa TT / Đã TT · export.
class KeToanTrackingPanel extends StatefulWidget {
  final KeToanTrackingStore store;
  final String userName;

  const KeToanTrackingPanel({super.key, required this.store, required this.userName});

  @override
  State<KeToanTrackingPanel> createState() => KeToanTrackingPanelState();
}

class KeToanTrackingPanelState extends State<KeToanTrackingPanel> with TickerProviderStateMixin {
  static const String _gsmParentKey = 'debt_gsm';

  static const List<(String key, String label)> _railMainBeforeGsm = [
    ('all', 'Tất cả BH / nợ / VinFast'),
    ('debt_insurance', 'Bảo hiểm thanh toán (I)'),
    ('warranty_vinfast', 'Bảo hành VinFast (W)'),
  ];

  static const List<(String key, String label)> _gsmSubCategories = [
    ('debt_gsm_bao_duong', 'Bảo dưỡng'),
    ('debt_gsm_thay_the_pt', 'Thay thế PT'),
    ('debt_gsm_son', 'Sơn'),
    ('debt_gsm_khac', 'Khác'),
  ];

  static const List<MapEntry<String, String>> _filterCols = [
    MapEntry('bienSo', 'Biển số'),
    MapEntry('roCode', 'Mã RO'),
    MapEntry('title', 'Tiêu đề'),
    MapEntry('category', 'Danh mục'),
    MapEntry('debtCreditor', 'Bên nợ'),
    MapEntry('gsmType', 'Loại GSM'),
    MapEntry('amount', 'Số tiền'),
    MapEntry('note', 'Ghi chú'),
    MapEntry('updated', 'Cập nhật'),
  ];

  late TabController _payTabCtrl;
  final Map<String, TextEditingController> _col = {};
  final ScrollController _hScroll = ScrollController();
  final ScrollController _vScroll = ScrollController();
  String _categoryKey = 'all';
  bool _gsmNavExpanded = false;
  final Set<String> _selectedIds = {};

  static bool _isGsmSubCategory(String key) => key.startsWith('debt_gsm_') && key != _gsmParentKey;

  @override
  void initState() {
    super.initState();
    for (final e in _filterCols) {
      _col[e.key] = TextEditingController();
    }
    _payTabCtrl = TabController(length: 2, vsync: this);
    _categoryKey = widget.store.focusCategoryKey;
    _gsmNavExpanded = _isGsmSubCategory(_categoryKey);
    _payTabCtrl.addListener(() {
      if (!_payTabCtrl.indexIsChanging) {
        setState(() => _selectedIds.clear());
      }
    });
    widget.store.addListener(_onStoreChanged);
  }

  void _onStoreChanged() {
    if (mounted) {
      setState(() {
        _categoryKey = widget.store.focusCategoryKey;
        if (_isGsmSubCategory(_categoryKey)) _gsmNavExpanded = true;
      });
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChanged);
    _payTabCtrl.dispose();
    _hScroll.dispose();
    _vScroll.dispose();
    for (final c in _col.values) {
      c.dispose();
    }
    super.dispose();
  }

  void focusCategory(String key) {
    setState(() {
      _categoryKey = key;
      if (_isGsmSubCategory(key)) _gsmNavExpanded = true;
      _selectedIds.clear();
      _payTabCtrl.index = 0;
    });
  }

  void _selectCategory(String key) {
    setState(() {
      _categoryKey = key;
      if (_isGsmSubCategory(key)) _gsmNavExpanded = true;
      _selectedIds.clear();
    });
  }

  List<KtTrackingEntry> get _baseRows => widget.store.query(
        paidTab: _payTabCtrl.index == 1,
        categoryKey: _categoryKey,
        searchQuery: '',
      );

  List<KtTrackingEntry> get _visibleRows {
    final filters = _filterCols.map((e) => _col[e.key]!.text).toList();
    return _baseRows.where((e) => cellsMatchFilters(filters, _rowCells(e))).toList();
  }

  String _categoryLabel(KtTrackingEntry e) {
    return trackingCategoryLabel(
      e.categoryKey,
      debtCreditor: e.debtCreditor,
      gsmDebtType: e.gsmDebtType,
    );
  }

  String _debtCreditorCell(KtTrackingEntry e) {
    if (e.categoryKey == 'debt_insurance' || e.payerKind == 'insurance') {
      final name = e.debtCreditor.isNotEmpty
          ? e.debtCreditor
          : (insuranceCompanyFromTrackingNote(e.note) ?? '');
      return name.isEmpty ? '—' : name;
    }
    if (!trackingEntryIsDebt(e) && e.debtCreditor.isEmpty) return '—';
    if (e.debtCreditor.isEmpty) return 'Chưa phân loại';
    return DebtCreditor.label(e.debtCreditor);
  }

  String _gsmTypeCell(KtTrackingEntry e) {
    if (e.debtCreditor != DebtCreditor.gsm) return '—';
    if (e.gsmDebtType.isEmpty) return 'Chưa chọn';
    return GsmDebtType.label(e.gsmDebtType);
  }

  List<String> _rowCells(KtTrackingEntry e) {
    return [
      e.bienSo,
      e.roCode.isEmpty ? e.reference : e.roCode,
      e.title,
      _categoryLabel(e),
      _debtCreditorCell(e),
      _gsmTypeCell(e),
      e.amount.toStringAsFixed(0),
      e.note,
      _formatTs(e.updatedAt),
    ];
  }

  Widget _filterHdr(String key, String title) {
    return ColumnFilterMenuHeader(
      title: title,
      filterController: _col[key]!,
      onFiltersChanged: () => setState(() {}),
    );
  }

  Future<void> _exportVisible() async {
    final rows = _visibleRows;
    if (rows.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không có dòng để xuất.'), backgroundColor: Colors.orange),
        );
      }
      return;
    }
    final csv = widget.store.exportCsv(rows);
    final tab = _payTabCtrl.index == 1 ? 'da_tt' : 'chua_tt';
    final defaultName = 'ke_toan_theo_doi_${tab}_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.csv';
    final result = await saveCsvExport(
      content: csv,
      fileName: defaultName,
      dialogTitle: 'Theo dõi kế toán',
    );
    if (mounted) {
      showCrossPlatformSaveSnackBar(
        context,
        result,
        defaultName,
        successExtra: result.ok ? '${rows.length} dòng' : null,
      );
    }
  }

  Future<void> _markSelectedPaid() async {
    if (_selectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chọn ít nhất một dòng chưa thanh toán.'), backgroundColor: Colors.orange),
      );
      return;
    }

    final selected = widget.store.all.where((e) => _selectedIds.contains(e.id)).toList();
    final debtRows = selected.where(trackingEntryIsDebt).toList();
    DebtPaidClassification? classification;

    if (debtRows.isNotEmpty) {
      classification = await showDebtPaidClassificationDialog(
        context,
        debtLineCount: debtRows.length,
      );
      if (classification == null) return;
    }

    try {
      await widget.store.markPaid(
        _selectedIds.toList(),
        debtClassification: classification,
      );
      setState(() => _selectedIds.clear());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              debtRows.isNotEmpty
                  ? 'Đã phân loại công nợ và chuyển ${selected.length} dòng sang «Đã thanh toán».'
                  : 'Đã chuyển sang «Đã thanh toán».',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi lưu: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _wrapTableScroll(DataTable table) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Scrollbar(
        controller: _hScroll,
        thumbVisibility: true,
        trackVisibility: true,
        child: SingleChildScrollView(
          controller: _hScroll,
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 280),
            child: Scrollbar(
              controller: _vScroll,
              thumbVisibility: true,
              trackVisibility: true,
              child: SingleChildScrollView(
                controller: _vScroll,
                scrollDirection: Axis.vertical,
                child: table,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTrackingTable() {
    final unpaidTab = _payTabCtrl.index == 0;
    final baseCount = _baseRows.length;
    final items = _visibleRows;
    final emptyFilter = baseCount > 0 && items.isEmpty;

    final allKeys = items.map((e) => e.id).toSet();
    final allSelected = unpaidTab && allKeys.isNotEmpty && allKeys.every((k) => _selectedIds.contains(k));

    final table = DataTable(
      headingRowColor: MaterialStateProperty.all(unpaidTab ? Colors.orange.shade50 : Colors.green.shade50),
      columnSpacing: 14,
      dataRowMinHeight: 44,
      dataRowMaxHeight: 72,
      columns: [
        if (unpaidTab)
          DataColumn(
            label: Checkbox(
              value: allSelected,
              onChanged: (_) {
                setState(() {
                  if (allSelected) {
                    _selectedIds.removeAll(allKeys);
                  } else {
                    _selectedIds.addAll(allKeys);
                  }
                });
              },
            ),
          ),
        DataColumn(label: _filterHdr('bienSo', 'Biển số')),
        DataColumn(label: _filterHdr('roCode', 'Mã RO')),
        DataColumn(label: _filterHdr('title', 'Tiêu đề')),
        DataColumn(label: _filterHdr('category', 'Danh mục')),
        DataColumn(label: _filterHdr('debtCreditor', 'Bên nợ')),
        DataColumn(label: _filterHdr('gsmType', 'Loại GSM')),
        DataColumn(label: _filterHdr('amount', 'Số tiền')),
        DataColumn(label: _filterHdr('note', 'Ghi chú')),
        DataColumn(label: _filterHdr('updated', 'Cập nhật')),
      ],
      rows: items.map((e) {
        final checked = _selectedIds.contains(e.id);
        final ro = e.roCode.isEmpty ? e.reference : e.roCode;
        return DataRow(
          selected: checked,
          onSelectChanged: unpaidTab
              ? (v) {
                  setState(() {
                    if (v == true) {
                      _selectedIds.add(e.id);
                    } else {
                      _selectedIds.remove(e.id);
                    }
                  });
                }
              : null,
          cells: [
            if (unpaidTab)
              DataCell(
                Checkbox(
                  value: checked,
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        _selectedIds.add(e.id);
                      } else {
                        _selectedIds.remove(e.id);
                      }
                    });
                  },
                ),
              ),
            DataCell(Text(e.bienSo, style: const TextStyle(fontWeight: FontWeight.w600))),
            DataCell(SelectableText(ro)),
            DataCell(
              SizedBox(
                width: 200,
                child: Text(
                  e.title.isEmpty ? '—' : e.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            DataCell(Text(_categoryLabel(e), style: const TextStyle(fontSize: 13))),
            DataCell(Text(_debtCreditorCell(e), style: const TextStyle(fontSize: 13))),
            DataCell(Text(_gsmTypeCell(e), style: const TextStyle(fontSize: 13))),
            DataCell(
              Text(
                _formatVnd(e.amount),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            DataCell(
              SizedBox(
                width: 220,
                child: Text(
                  e.note.isEmpty ? '—' : e.note,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
            DataCell(Text(_formatTs(e.updatedAt), style: TextStyle(fontSize: 12, color: Colors.grey.shade700))),
          ],
        );
      }).toList(),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _wrapTableScroll(table)),
        if (baseCount == 0 || emptyFilter)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Text(
              baseCount == 0
                  ? (unpaidTab
                      ? 'Không có khoản chưa thanh toán. Sau «Xác nhận đã thu tiền» (có BH/nợ/VinFast) dòng sẽ hiện ở đây.'
                      : 'Chưa có khoản đã thanh toán trong danh mục này.')
                  : 'Không có dòng khớp lọc cột. Mở menu tam giác trên tiêu đề cột → «Xóa lọc cột».',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
            ),
          ),
      ],
    );
  }

  Widget _buildCategoryDropdown() {
    final options = <(String, String)>[
      ..._railMainBeforeGsm,
      (_gsmParentKey, 'Công nợ GSM (tất cả)'),
      if (_gsmNavExpanded) ..._gsmSubCategories,
      ('debt_other', 'Công nợ khác'),
    ];
    return DropdownButtonFormField<String>(
      value: _categoryKey,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Danh mục theo dõi',
        border: OutlineInputBorder(),
        isDense: true,
        filled: true,
        fillColor: Colors.white,
      ),
      items: [
        for (final o in options)
          DropdownMenuItem(value: o.$1, child: Text(o.$2, maxLines: 2, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: (v) {
        if (v != null) _selectCategory(v);
      },
    );
  }

  Widget _buildTrackingToolbarAndTable(bool unpaidTab) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: _exportVisible,
              icon: const Icon(Icons.download),
              label: Text(exportActionLabel(desktop: 'Export CSV', web: 'Tải CSV', mobile: 'Chia sẻ CSV')),
            ),
            if (unpaidTab)
              FilledButton.icon(
                onPressed: _selectedIds.isEmpty ? null : _markSelectedPaid,
                icon: const Icon(Icons.done_all),
                label: Text('Đã TT (${_selectedIds.length})'),
                style: FilledButton.styleFrom(backgroundColor: Colors.teal.shade700),
              ),
            Text(
              unpaidTab
                  ? 'Lọc cột (tam giác) · tích dòng → đánh dấu đã TT.'
                  : 'Danh sách đã đối soát.',
              style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade700),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(child: _buildTrackingTable()),
      ],
    );
  }

  Widget _buildCategorySidebar(bool narrow) {
    final railWidth = narrow ? 56.0 : 208.0;

    return Material(
      color: const Color(0xFFE0F2F1),
      child: SizedBox(
        width: railWidth,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            for (final c in _railMainBeforeGsm)
              _categoryNavTile(key: c.$1, label: c.$2, icon: _iconForCategory(c.$1), narrow: narrow),
            _gsmParentNavTile(narrow),
            if (_gsmNavExpanded)
              for (final c in _gsmSubCategories)
                _categoryNavTile(
                  key: c.$1,
                  label: c.$2,
                  icon: Icons.phone_android,
                  narrow: narrow,
                  indent: narrow ? 0 : 20,
                  compact: true,
                ),
            _categoryNavTile(
              key: 'debt_other',
              label: 'Công nợ khác',
              icon: Icons.receipt_long,
              narrow: narrow,
            ),
          ],
        ),
      ),
    );
  }

  Widget _categoryNavTile({
    required String key,
    required String label,
    required IconData icon,
    required bool narrow,
    double indent = 0,
    bool compact = false,
  }) {
    final selected = _categoryKey == key;
    final fg = selected ? Colors.teal.shade900 : Colors.blueGrey.shade800;

    return Material(
      color: selected ? Colors.teal.shade100 : Colors.transparent,
      child: InkWell(
        onTap: () => _selectCategory(key),
        child: Padding(
          padding: EdgeInsets.fromLTRB(8 + indent, compact ? 6 : 10, 8, compact ? 6 : 10),
          child: narrow
              ? Tooltip(
                  message: compact ? 'GSM · $label' : label,
                  child: Icon(icon, size: compact ? 20 : 22, color: fg),
                )
              : Row(
                  children: [
                    Icon(icon, size: compact ? 20 : 22, color: fg),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        compact ? 'GSM · $label' : label,
                        maxLines: 2,
                        style: TextStyle(
                          fontSize: compact ? 13 : 14,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                          color: fg,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _gsmParentNavTile(bool narrow) {
    final parentSelected = _categoryKey == _gsmParentKey;
    final subSelected = _isGsmSubCategory(_categoryKey);
    final fg = (parentSelected || subSelected) ? Colors.teal.shade900 : Colors.blueGrey.shade800;

    return Material(
      color: parentSelected
          ? Colors.teal.shade100
          : subSelected
              ? Colors.teal.shade50
              : Colors.transparent,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => _selectCategory(_gsmParentKey),
              child: Padding(
                padding: EdgeInsets.fromLTRB(8, narrow ? 8 : 10, 0, narrow ? 8 : 10),
                child: narrow
                    ? Tooltip(
                        message: 'Công nợ GSM (tất cả)',
                        child: Icon(Icons.phone_android, size: 22, color: fg),
                      )
                    : Row(
                        children: [
                          Icon(Icons.phone_android, size: 22, color: fg),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Công nợ GSM (tất cả)',
                              maxLines: 2,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: parentSelected ? FontWeight.w600 : FontWeight.normal,
                                color: fg,
                                height: 1.2,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            tooltip: _gsmNavExpanded ? 'Thu gọn loại GSM' : 'Mở loại GSM',
            icon: Icon(
              _gsmNavExpanded ? Icons.expand_less : Icons.expand_more,
              size: 22,
              color: Colors.teal.shade800,
            ),
            onPressed: () => setState(() => _gsmNavExpanded = !_gsmNavExpanded),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.store.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final unpaidTab = _payTabCtrl.index == 0;
    final phone = appIsPhone(context);
    final narrow = phone || MediaQuery.sizeOf(context).width < 960;
    final nChua = widget.store.query(paidTab: false, categoryKey: 'all', searchQuery: '').length;
    final nDa = widget.store.query(paidTab: true, categoryKey: 'all', searchQuery: '').length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.teal.shade50,
          child: TabBar(
            controller: _payTabCtrl,
            labelColor: Colors.teal.shade900,
            unselectedLabelColor: Colors.teal.shade700,
            indicatorColor: Colors.teal.shade800,
            onTap: (_) => setState(() => _selectedIds.clear()),
            tabs: [
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.pending_actions, size: 18),
                    const SizedBox(width: 6),
                    Text('Chưa thanh toán ($nChua)'),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle_outline, size: 18),
                    const SizedBox(width: 6),
                    Text('Đã thanh toán ($nDa)'),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: phone
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: _buildCategoryDropdown(),
                    ),
                    Expanded(
                      child: Padding(
                        padding: appScreenPadding(context),
                        child: _buildTrackingToolbarAndTable(unpaidTab),
                      ),
                    ),
                  ],
                )
              : Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildCategorySidebar(narrow),
              const VerticalDivider(width: 1),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: _buildTrackingToolbarAndTable(unpaidTab),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static IconData _iconForCategory(String key) {
    if (key.startsWith('debt_gsm')) return Icons.phone_android;
    switch (key) {
      case 'debt_insurance':
        return Icons.shield;
      case 'warranty_vinfast':
        return Icons.directions_car;
      case 'debt_other':
        return Icons.receipt_long;
      default:
        return Icons.list_alt;
    }
  }

  static String _formatVnd(double v) {
    final s = v.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
    return '$s đ';
  }

  static String _formatTs(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    return DateFormat('dd/MM/yyyy HH:mm').format(d);
  }
}
