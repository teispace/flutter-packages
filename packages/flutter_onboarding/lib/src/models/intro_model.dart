import 'package:flutter/material.dart';

/// One page of the onboarding flow.
///
/// Every part is a [Widget] rather than a `String` or an `ImageProvider`, so a
/// page can be as plain or as elaborate as the app needs — a styled
/// [RichText] title, an SVG, a Lottie animation — without this package
/// needing to know about any of them.
class IntroModel {
  /// Creates a page.
  IntroModel({
    required this.title,
    required this.description,
    required this.image,
  });

  /// The title section of the page. This is typically a [Text] widget.
  final Widget title;

  /// The description section of the page. This is typically a [Text] widget.
  final Widget description;

  /// The image section of the page. This is typically an [Image] widget.
  final Widget image;
}
