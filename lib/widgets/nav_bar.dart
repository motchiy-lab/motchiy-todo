import 'package:flutter/material.dart';

class NavItem extends StatefulWidget {
  final int index;
  final IconData outlineIcon;
  final IconData filledIcon;
  final String label;
  final int currentIndex;
  final Color? selectedColor;
  final ValueChanged<int> onTap;

  const NavItem({
    super.key,
    required this.index,
    required this.outlineIcon,
    required this.filledIcon,
    required this.label,
    required this.currentIndex,
    this.selectedColor,
    required this.onTap,
  });

  @override
  State<NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<NavItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isSelected = widget.currentIndex == widget.index;
    final colorScheme = Theme.of(context).colorScheme;
    final color = isSelected
        ? (widget.selectedColor ?? colorScheme.primary)
        : Colors.grey;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onTap(widget.index),
        child: SizedBox(
          width: 50,
          height: 55,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Positioned(
                top: 10,
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(
                    begin: 1.0,
                    end: _isHovered ? 1.15 : 1.0,
                  ),
                  duration: const Duration(milliseconds: 150),
                  builder: (context, scale, child) {
                    return Transform.scale(scale: scale, child: child);
                  },
                  child: Icon(
                    isSelected ? widget.filledIcon : widget.outlineIcon,
                    color: color,
                    size: 22,
                  ),
                ),
              ),
              if (_isHovered)
                Positioned(
                  bottom: 10,
                  child: Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: color,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class CenterNavItem extends StatefulWidget {
  final int index;
  final IconData filledIcon;
  final String label;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const CenterNavItem({
    super.key,
    required this.index,
    required this.filledIcon,
    required this.label,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  State<CenterNavItem> createState() => _CenterNavItemState();
}

class _CenterNavItemState extends State<CenterNavItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isSelected = widget.currentIndex == widget.index;
    final colorScheme = Theme.of(context).colorScheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onTap(widget.index),
        child: SizedBox(
          width: 70,
          height: 65,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Positioned(
                top: 2,
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(
                    begin: 1.0,
                    end: _isHovered ? 1.12 : 1.0,
                  ),
                  duration: const Duration(milliseconds: 150),
                  builder: (context, scale, child) {
                    return Transform.scale(scale: scale, child: child);
                  },
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: colorScheme.primary.withValues(alpha: 0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Icon(
                      widget.filledIcon,
                      color: colorScheme.onPrimary,
                      size: 26,
                    ),
                  ),
                ),
              ),
              if (_isHovered)
                Positioned(
                  bottom: 0,
                  child: Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: isSelected
                          ? colorScheme.primary
                          : Colors.grey[700],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
