import 'package:flutter/material.dart';

/// A pill-shaped button, filled or outlined.
///
/// Used for the skip and next controls. It takes a [child] rather than a
/// label so the caller can put an icon, a row, or styled text in it.
class CustomRoundedButton extends StatelessWidget {
  /// Creates a rounded button.
  const CustomRoundedButton({
    required this.child,
    required this.color,
    super.key,
    this.onTap,
    this.shouldFill = true,
    this.radius = 100,
    this.width,
    this.height,
  });

  /// What the button shows. Usually a [Text].
  final Widget child;

  /// The fill when [shouldFill] is true, and the border when it is not.
  final Color color;

  /// Whether the button is filled. False draws it as an outline.
  final bool shouldFill;

  /// Called when the button is tapped. Null disables it.
  final VoidCallback? onTap;

  /// Corner radius. The default is large enough to read as a pill.
  final double radius;

  /// Fixed width, or null to size to the [child].
  final double? width;

  /// Fixed height, or null to size to the [child].
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: shouldFill ? color : null,
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: color,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
