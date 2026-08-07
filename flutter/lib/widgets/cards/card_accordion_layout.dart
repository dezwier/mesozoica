import 'package:flutter/material.dart';

typedef CardAccordionItemBuilder = Widget Function(
  BuildContext context,
  bool isOpen,
  double curvedT,
  double Function(double start, double end) lerpFn,
);

class CardAccordionItem {
  final CardAccordionItemBuilder builder;

  const CardAccordionItem({
    required this.builder,
  });
}

class CardAccordionLayout extends StatefulWidget {
  const CardAccordionLayout({
    super.key,
    required this.items,
    this.initialIndex = 0,
  });

  final List<CardAccordionItem> items;
  final int initialIndex;

  @override
  State<CardAccordionLayout> createState() => _CardAccordionLayoutState();
}

class _CardAccordionLayoutState extends State<CardAccordionLayout> with TickerProviderStateMixin {
  late int _expandedIndex;
  late int _previousIndex;
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _expandedIndex = widget.initialIndex;
    _previousIndex = widget.initialIndex;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _controller.value = 1.0;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CardAccordionLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_expandedIndex >= widget.items.length) {
      _expandedIndex = 0;
      _previousIndex = 0;
      _controller.value = 1.0;
    }
  }

  void _onTapIndex(int index) {
    if (index == _expandedIndex) return;
    setState(() {
      _previousIndex = _expandedIndex;
      _expandedIndex = index;
      _controller.forward(from: 0.0);
    });
  }

  double _getWeight(int index, double t) {
    const closedW = 1.0;
    const openW = 3.5;

    if (index == _expandedIndex) {
      return closedW + (openW - closedW) * t;
    } else if (index == _previousIndex) {
      return openW + (closedW - openW) * t;
    } else {
      return closedW;
    }
  }

  double _lerpValue(int index, double start, double end, double t) {
    if (index == _expandedIndex) {
      return start + (end - start) * t;
    } else if (index == _previousIndex) {
      return end + (start - end) * t;
    } else {
      return start;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final double curvedT = const Cubic(0.2, 0.0, 0.2, 1.0).transform(_controller.value);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (int i = 0; i < widget.items.length; i++) ...[
              if (i > 0) const SizedBox(height: 6),
              Expanded(
                flex: (_getWeight(i, curvedT) * 1000).round(),
                child: GestureDetector(
                  onTap: _expandedIndex == i ? null : () => _onTapIndex(i),
                  behavior: HitTestBehavior.opaque,
                  child: widget.items[i].builder(
                    context,
                    _expandedIndex == i,
                    curvedT,
                    (start, end) => _lerpValue(i, start, end, curvedT),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
