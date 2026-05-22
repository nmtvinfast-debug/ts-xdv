import 'package:flutter/material.dart';

import '../core/responsive_layout.dart';

/// Danh sách + chi tiết: mobile chỉ hiện một pane; desktop chia đôi.
class ResponsiveMasterDetail extends StatelessWidget {
  const ResponsiveMasterDetail({
    super.key,
    required this.listPane,
    required this.detailPane,
    required this.detailVisible,
    this.onBackFromDetail,
    this.listWidth = 360,
    this.backLabel = 'Danh sách xe',
  });

  final Widget listPane;
  final Widget detailPane;
  final bool detailVisible;
  final VoidCallback? onBackFromDetail;
  final double listWidth;
  final String backLabel;

  @override
  Widget build(BuildContext context) {
    final phone = appFormFactor(context) == AppFormFactor.phone;

    if (phone) {
      if (!detailVisible) {
        return listPane;
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.white,
            elevation: 1,
            child: SafeArea(
              bottom: false,
              child: ListTile(
                dense: true,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: onBackFromDetail,
                ),
                title: Text(backLabel, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              ),
            ),
          ),
          Expanded(child: detailPane),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: listWidth, child: listPane),
        const VerticalDivider(width: 1, thickness: 1),
        Expanded(child: detailPane),
      ],
    );
  }
}

/// Hai cột ngang (Quản đốc, Bảo vệ…): mobile xếp dọc.
class ResponsiveTwoColumns extends StatelessWidget {
  const ResponsiveTwoColumns({
    super.key,
    required this.first,
    required this.second,
    this.firstFlex = 1,
    this.secondFlex = 1,
    this.gap = 8,
  });

  final Widget first;
  final Widget second;
  final int firstFlex;
  final int secondFlex;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final phone = appFormFactor(context) == AppFormFactor.phone;
    if (phone) {
      return Column(
        children: [
          Expanded(flex: firstFlex, child: first),
          SizedBox(height: gap),
          Expanded(flex: secondFlex, child: second),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: firstFlex, child: first),
        SizedBox(width: gap),
        Expanded(flex: secondFlex, child: second),
      ],
    );
  }
}

/// NavigationRail trên desktop / BottomNavigationBar trên điện thoại.
class ResponsiveNavScaffold extends StatelessWidget {
  const ResponsiveNavScaffold({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    required this.body,
    this.railBackgroundColor,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<NavigationDestination> destinations;
  final Widget body;
  final Color? railBackgroundColor;

  @override
  Widget build(BuildContext context) {
    final phone = appFormFactor(context) == AppFormFactor.phone;
    if (phone) {
      return Column(
        children: [
          Expanded(child: body),
          NavigationBar(
            selectedIndex: selectedIndex,
            onDestinationSelected: onDestinationSelected,
            destinations: destinations,
          ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NavigationRail(
          selectedIndex: selectedIndex,
          onDestinationSelected: onDestinationSelected,
          labelType: NavigationRailLabelType.all,
          backgroundColor: railBackgroundColor ?? Colors.white,
          destinations: [
            for (final d in destinations)
              NavigationRailDestination(
                icon: d.icon,
                selectedIcon: d.selectedIcon ?? d.icon,
                label: Text(d.label),
              ),
          ],
        ),
        const VerticalDivider(width: 1, thickness: 1),
        Expanded(child: body),
      ],
    );
  }
}

/// Tiêu đề AppBar ngắn trên mobile.
String compactAppBarTitle(BuildContext context, String fullTitle) {
  if (appFormFactor(context) == AppFormFactor.phone) {
    final parts = fullTitle.split('—');
    if (parts.length > 1) return parts.first.trim();
    if (fullTitle.length > 28) return '${fullTitle.substring(0, 26)}…';
  }
  return fullTitle;
}
