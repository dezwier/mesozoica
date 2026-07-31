import 'package:flutter/material.dart';

import 'drawer_sheet_sizes.dart';

class DraggableSheetWrapper extends StatefulWidget {
  const DraggableSheetWrapper({
    super.key,
    required this.childBuilder,
    this.initialChildSize = DrawerSheetSizes.initialChildSize,
    this.minChildSize = DrawerSheetSizes.minChildSize,
    this.maxChildSize = DrawerSheetSizes.maxChildSize,
  });

  final Widget Function(ScrollController scrollController) childBuilder;
  final double initialChildSize;
  final double minChildSize;
  final double maxChildSize;

  @override
  State<DraggableSheetWrapper> createState() => _DraggableSheetWrapperState();
}

class _DraggableSheetWrapperState extends State<DraggableSheetWrapper> {
  late final DraggableScrollableController _sheetController;

  @override
  void initState() {
    super.initState();
    _sheetController = DraggableScrollableController();
    _sheetController.addListener(_onSheetSizeChanged);
  }

  void _onSheetSizeChanged() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    if (_sheetController.size <= widget.minChildSize) {
      _sheetController.removeListener(_onSheetSizeChanged);
      if (route.isActive) {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  void dispose() {
    _sheetController.removeListener(_onSheetSizeChanged);
    _sheetController.dispose();
    super.dispose();
  }

  List<double>? get _snapSizes {
    // snapSizes must be strictly between min and max (Flutter requirement).
    final sizes = <double>{};
    if (widget.initialChildSize > widget.minChildSize &&
        widget.initialChildSize < widget.maxChildSize) {
      sizes.add(widget.initialChildSize);
    }
    if (sizes.isEmpty) return null;
    return sizes.toList()..sort();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      controller: _sheetController,
      initialChildSize: widget.initialChildSize,
      minChildSize: widget.minChildSize,
      maxChildSize: widget.maxChildSize,
      expand: false,
      snap: true,
      snapSizes: _snapSizes,
      builder: (context, scrollController) =>
          widget.childBuilder(scrollController),
    );
  }
}
