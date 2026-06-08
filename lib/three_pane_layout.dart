import 'package:flutter/material.dart';

class ThreePaneLayout extends StatefulWidget {
  final Widget leftChild;
  final Widget middleChild;
  final Widget rightChild;
  final double initialSplitRatio1;
  final double initialSplitRatio2;

  const ThreePaneLayout({
    super.key,
    required this.leftChild,
    required this.middleChild,
    required this.rightChild,
    this.initialSplitRatio1 = 0.3,
    this.initialSplitRatio2 = 0.7,
  });

  @override
  State<ThreePaneLayout> createState() => _ThreePaneLayoutState();
}

class _ThreePaneLayoutState extends State<ThreePaneLayout> {
  late double _splitRatio1;
  late double _splitRatio2;

  @override
  void initState() {
    super.initState();
    _splitRatio1 = widget.initialSplitRatio1;
    _splitRatio2 = widget.initialSplitRatio2;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final leftWidth = (_splitRatio1 * totalWidth).clamp(
          100.0,
          totalWidth - 200.0,
        );
        final middleWidth = ((_splitRatio2 - _splitRatio1) * totalWidth).clamp(
          100.0,
          totalWidth - 200.0,
        );

        return Row(
          children: [
            SizedBox(
              width: leftWidth,
              child: widget.leftChild,
            ),
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragUpdate: (details) {
                setState(() {
                  _splitRatio1 += details.delta.dx / totalWidth;
                  _splitRatio1 = _splitRatio1.clamp(0.1, _splitRatio2 - 0.05);
                });
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeLeftRight,
                child: VerticalDivider(
                  width: 8.0,
                  thickness: 1.0,
                  color: Theme.of(context).dividerColor,
                ),
              ),
            ),
            SizedBox(
              width: middleWidth,
              child: widget.middleChild,
            ),
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragUpdate: (details) {
                setState(() {
                  _splitRatio2 += details.delta.dx / totalWidth;
                  _splitRatio2 = _splitRatio2.clamp(_splitRatio1 + 0.05, 0.9);
                });
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeLeftRight,
                child: VerticalDivider(
                  width: 8.0,
                  thickness: 1.0,
                  color: Theme.of(context).dividerColor,
                ),
              ),
            ),
            Expanded(
              child: widget.rightChild,
            ),
          ],
        );
      },
    );
  }
}
