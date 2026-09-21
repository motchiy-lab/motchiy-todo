import 'package:flutter/material.dart';

class NavItem extends StatelessWidget {
  final int index;
  final IconData outlineIcon;
  final IconData filledIcon;
  final String label;
  final bool showLabel;
  final int currentIndex;
  final Color? selectedColor;
  final ValueChanged<int> onTap;

  const NavItem({
    super.key,
    required this.index,
    required this.outlineIcon,
    required this.filledIcon,
    required this.label,
    required this.showLabel,
    required this.currentIndex,
    this.selectedColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = currentIndex == index;
    final colorScheme = Theme.of(context).colorScheme;
    final color = isSelected
        ? (selectedColor ?? colorScheme.onPrimary)
        : Colors.grey;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onTap(index),
      child: SizedBox(
        height: 80,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isSelected ? filledIcon : outlineIcon,
                  color: color,
                  size: 22,
                ),
                if (showLabel) ...[
                  const SizedBox(height: 2),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: color,
                      fontSize: 10,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
