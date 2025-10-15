import 'dart:math' as math;

import 'package:flutter/widgets.dart';

class FourColSpec {
  const FourColSpec(this.c1, this.c2, this.c3, this.c4, {this.gutter = 0});

  final double c1;
  final double c2;
  final double c3;
  final double c4;
  final double gutter;

  double operator [](int index) {
    switch (index) {
      case 0:
        return c1;
      case 1:
        return c2;
      case 2:
        return c3;
      case 3:
        return c4;
      default:
        throw RangeError.index(index, this, 'index', null, 4);
    }
  }

  double get total => c1 + c2 + c3 + c4;
}

typedef FourColBuilder = Widget Function(
    BuildContext context, FourColSpec spec);

class FourColLayout extends StatelessWidget {
  const FourColLayout({
    required this.builder,
    this.padding = const EdgeInsets.symmetric(horizontal: 12),
    this.minC1 = 130,
    this.minC2 = 130,
    this.minC3 = 200,
    this.minC4 = 200,
    this.flexes = const [3, 3, 4, 4],
    this.gutter = 0,
    super.key,
  }) : assert(flexes.length == 4);

  final FourColBuilder builder;
  final EdgeInsetsGeometry padding;
  final double minC1;
  final double minC2;
  final double minC3;
  final double minC4;
  final List<int> flexes;
  final double gutter;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final resolvedPadding = padding.resolve(Directionality.of(ctx));
        final availableWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.of(ctx).size.width;
        final totalGutter = gutter <= 0 ? 0 : gutter * 3;
        final usableWidth = math.max(
          0,
          availableWidth - resolvedPadding.horizontal - totalGutter,
        );

        final totalFlex = flexes.fold<int>(0, (sum, value) => sum + value);
        double columnWidth(int index) =>
            totalFlex == 0 ? 0 : usableWidth * flexes[index] / totalFlex;
        var c1 = columnWidth(0);
        var c2 = columnWidth(1);
        var c3 = columnWidth(2);
        var c4 = columnWidth(3);

        final mins = [minC1, minC2, minC3, minC4];
        final minSum = mins.fold<double>(0, (sum, value) => sum + value);
        if (usableWidth <= 0) {
          c1 = c2 = c3 = c4 = 0;
        } else if (usableWidth < minSum && minSum > 0) {
          final factor = usableWidth / minSum;
          c1 = minC1 * factor;
          c2 = minC2 * factor;
          c3 = minC3 * factor;
          c4 = minC4 * factor;
        } else if (c1 < minC1 || c2 < minC2 || c3 < minC3 || c4 < minC4) {
          final remainingWidth =
              usableWidth > minSum ? usableWidth - minSum : 0;
          final surpluses = [
            math.max(0.0, c1 - minC1),
            math.max(0.0, c2 - minC2),
            math.max(0.0, c3 - minC3),
            math.max(0.0, c4 - minC4),
          ];
          final surplusTotal =
              surpluses.fold<double>(0, (sum, value) => sum + value);
          double distribute(int index) {
            if (surplusTotal == 0) {
              return remainingWidth / 4;
            }
            return remainingWidth * (surpluses[index] / surplusTotal);
          }

          c1 = minC1 + distribute(0);
          c2 = minC2 + distribute(1);
          c3 = minC3 + distribute(2);
          c4 = minC4 + distribute(3);
        }

        final spec = FourColSpec(
          c1,
          c2,
          c3,
          c4,
          gutter: math.max(0, gutter),
        );
        return Padding(
          padding: resolvedPadding,
          child: builder(ctx, spec),
        );
      },
    );
  }
}
