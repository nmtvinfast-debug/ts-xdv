import 'package:flutter/material.dart';

/// Tiêu đề cột + tam giác mở menu (Lọc theo / Xóa lọc / sắp xếp).
class ColumnFilterMenuHeader extends StatelessWidget {
  final String title;
  final TextEditingController filterController;
  final VoidCallback onFiltersChanged;
  final VoidCallback? onSortAsc;
  final VoidCallback? onSortDesc;

  const ColumnFilterMenuHeader({
    super.key,
    required this.title,
    required this.filterController,
    required this.onFiltersChanged,
    this.onSortAsc,
    this.onSortDesc,
  });

  Future<void> _openFilterDialog(BuildContext context) async {
    final tmp = TextEditingController(text: filterController.text);
    await showDialog<void>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text('Lọc: $title'),
        content: TextField(
          controller: tmp,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Chứa chuỗi…',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onSubmitted: (_) {
            filterController.text = tmp.text;
            Navigator.pop(dCtx);
            onFiltersChanged();
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () {
              filterController.text = tmp.text;
              Navigator.pop(dCtx);
              onFiltersChanged();
            },
            child: const Text('Áp dụng'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Không dùng [Expanded] trong tiêu đề [DataTable]: bảng giao ràng buộc ngang
    // khiến flex nhận bề rộng 0 → chữ tiêu đề biến mất (chỉ còn nền hàng header).
    final titleStyle = TextStyle(
      fontWeight: FontWeight.bold,
      color: Theme.of(context).colorScheme.onSurface,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          title,
          style: titleStyle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        PopupMenuButton<String>(
          tooltip: 'Tùy chọn cột',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          icon: Icon(Icons.arrow_drop_down, size: 22, color: Colors.grey.shade800),
          onSelected: (v) async {
            switch (v) {
              case 'sortAsc':
                onSortAsc?.call();
                if (onSortAsc == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Sắp xếp A→Z: chưa áp dụng cho cột này.'), duration: Duration(seconds: 2)),
                  );
                }
                break;
              case 'sortDesc':
                onSortDesc?.call();
                if (onSortDesc == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Sắp xếp Z→A: chưa áp dụng cho cột này.'), duration: Duration(seconds: 2)),
                  );
                }
                break;
              case 'filter':
                await _openFilterDialog(context);
                break;
              case 'clear':
                filterController.clear();
                onFiltersChanged();
                break;
            }
          },
          itemBuilder: (ctx) => [
            PopupMenuItem(
              value: 'sortAsc',
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.arrow_upward, size: 20),
                title: const Text('A đến Z'),
              ),
            ),
            PopupMenuItem(
              value: 'sortDesc',
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.arrow_downward, size: 20),
                title: const Text('Z đến A'),
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'filter',
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.filter_alt, size: 20, color: Colors.teal.shade700),
                title: const Text('Lọc theo'),
              ),
            ),
            if (filterController.text.trim().isNotEmpty)
              PopupMenuItem(
                value: 'clear',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.clear, size: 20),
                  title: const Text('Xóa lọc cột'),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Mỗi filter non-empty phải là substring của ô cùng index (không phân biệt hoa thường).
bool cellsMatchFilters(List<String> filters, List<String> cells) {
  final n = filters.length < cells.length ? filters.length : cells.length;
  for (var i = 0; i < n; i++) {
    final q = filters[i].trim().toLowerCase();
    if (q.isEmpty) continue;
    if (!cells[i].toLowerCase().contains(q)) return false;
  }
  return true;
}
