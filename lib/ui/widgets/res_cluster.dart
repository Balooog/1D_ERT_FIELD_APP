import 'package:flutter/material.dart';

import '../layout/inputs.dart';
import '../layout/sizing.dart';

Widget tinyIconButton({
  Key? key,
  required IconData icon,
  String? tooltip,
  VoidCallback? onPressed,
  Color? color,
}) {
  return IconButton(
    key: key,
    tooltip: tooltip,
    onPressed: onPressed,
    icon: Icon(icon, size: 18, color: color),
    style: IconButton.styleFrom(
      fixedSize: const Size(28, 28),
      padding: EdgeInsets.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
    ),
  );
}

Widget compactMenuButton<T>({
  Key? key,
  required List<PopupMenuEntry<T>> Function(BuildContext) itemBuilder,
  PopupMenuItemSelected<T>? onSelected,
  String? tooltip,
  IconData icon = Icons.more_vert,
  Offset offset = Offset.zero,
}) {
  return SizedBox(
    height: kFieldH,
    width: 28,
    child: Center(
      child: Tooltip(
        message: tooltip,
        waitDuration: const Duration(milliseconds: 400),
        child: PopupMenuButton<T>(
          key: key,
          padding: EdgeInsets.zero,
          iconSize: 18,
          offset: offset,
          icon: Icon(icon, size: 18),
          itemBuilder: itemBuilder,
          onSelected: onSelected,
        ),
      ),
    ),
  );
}

class ResCluster extends StatelessWidget {
  const ResCluster({
    super.key,
    required this.primary,
    this.accessories = const [],
    this.menu,
  });

  factory ResCluster.textField({
    Key? key,
    required TextEditingController controller,
    List<Widget> accessories = const [],
    Widget? menu,
    String hint = '',
    TextInputType keyboardType =
        const TextInputType.numberWithOptions(decimal: true),
    TextAlign textAlign = TextAlign.center,
  }) {
    return ResCluster(
      key: key,
      primary: TextField(
        controller: controller,
        maxLines: 1,
        keyboardType: keyboardType,
        textAlign: textAlign,
        textAlignVertical: TextAlignVertical.top,
        decoration: resFieldDecoration(hint),
      ),
      accessories: accessories,
      menu: menu,
    );
  }

  final Widget primary;
  final List<Widget> accessories;
  final Widget? menu;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      Expanded(
        child: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: SizedBox(
            height: kFieldH,
            child: primary,
          ),
        ),
      ),
    ];

    if (accessories.isNotEmpty) {
      children
        ..add(const SizedBox(width: 8))
        ..add(
          SizedBox(
            height: kFieldH,
            width: kRailW,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: accessories,
              ),
            ),
          ),
        );
    }

    if (menu != null) {
      children
        ..add(const SizedBox(width: 8))
        ..add(
          SizedBox(
            height: kFieldH,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Align(
                alignment: Alignment.center,
                child: menu,
              ),
            ),
          ),
        );
    }

    return SizedBox(
      height: kRowH,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}
