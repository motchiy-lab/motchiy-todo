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
    final highlightColor = selectedColor ?? colorScheme.onPrimary;
    final color = isSelected ? highlightColor : Colors.grey;
    final indicatorSize = showLabel ? 74.0 : 68.0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onTap(index),
      child: SizedBox(
        height: 80,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (isSelected)
              Positioned(
                top: 7,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  width: indicatorSize,
                  height: indicatorSize,
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.primary.withValues(alpha: 0.28),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    isSelected ? filledIcon : outlineIcon,
                    color: color,
                    size: 22,
                  ),
                  if (showLabel) ...[
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 12,
                      child: Center(
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontSize: 10.5,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                                color: color,
                                letterSpacing: 0.1,
                              ) ??
                              TextStyle(
                                color: color,
                                fontSize: 10.5,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
