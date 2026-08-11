import 'dart:async';

import 'package:dots_indicator/dots_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_onboarding/src/models/intro_model.dart';
import 'package:flutter_onboarding/src/widgets/custom_rounded_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A one-time onboarding flow.
///
/// Shows [pages] with a dots indicator and skip/next controls, and calls
/// [onDone] when the last page is finished. By default it also remembers
/// that it has been seen, so a second launch goes straight past it — set
/// [shouldUseDefaultStorage] to false to own that decision.
///
/// Note that **skip jumps to the last page rather than leaving the flow**,
/// so the final page is always seen and [onDone] has exactly one caller.
class FlutterOnBoarding extends StatefulWidget {
  /// Creates an onboarding flow over [pages].
  FlutterOnBoarding({
    required this.pages,
    required this.onDone,
    super.key,
    this.scrollDirection = Axis.vertical,
    this.physics = const BouncingScrollPhysics(),
    this.activeIndicatorShape,
    this.inactiveIndicatorShape,
    this.activeIndicatorSize,
    this.inactiveIndicatorSize,
    this.pageController,
    this.skipButtonText,
    this.nextButtonText,
    this.doneButtonText,
    this.indicator,
    this.navigationControl,
    this.indicatorActiveColor,
    this.indicatorInactiveColor,
    this.skipButtonColor,
    this.nextButtonColor,
    this.loadingWidget,
    this.shouldUseDefaultStorage = true,
  }) : assert(pages.isNotEmpty, 'You must provide at least one page.');

  /// The list of pages to display in the onboarding flow.
  /// Pages are of type [IntroModel], and are rendered in order.
  final List<IntroModel> pages;

  /// Which way the pages move.
  ///
  /// [Axis.horizontal] scrolls left to right, [Axis.vertical] top to
  /// bottom. The dots indicator follows it.
  final Axis scrollDirection;

  /// Scroll Physics. Defaults to [BouncingScrollPhysics].
  final ScrollPhysics? physics;

  /// Called when the done button on the last page is tapped.
  final VoidCallback onDone;

  //dot indicator decorators

  /// The shape of the dot indicator. Defaults to [RoundedRectangleBorder].
  final ShapeBorder? activeIndicatorShape;

  /// The shape of the dot indicator. Defaults to [RoundedRectangleBorder].
  final ShapeBorder? inactiveIndicatorShape;

  /// The size of the dot indicator. Defaults to [Size.square(10.0)].
  final Size? activeIndicatorSize;

  /// The size of the dot indicator. Defaults to [Size.square(10.0)].
  final Size? inactiveIndicatorSize;

  /// Page controller used to control the scrolling of the onboarding flow.
  final PageController? pageController;

  /// Skip Button Text
  final String? skipButtonText;

  /// Next Button Text
  final String? nextButtonText;

  /// Done Button Text
  final String? doneButtonText;

  /// The widget to show as the indicator. Defaults to [DotsIndicator].
  final Widget? indicator;

  /// Replaces the built-in skip and next controls.
  ///
  /// Supply this to drive the flow yourself; the [pageController] is how
  /// you move between pages.
  final Widget? navigationControl;

  /// Indicator active color. Defaults to [Theme.of(context).primaryColor].
  final Color? indicatorActiveColor;

  /// Indicator inactive color. Defaults to [Colors.grey].
  final Color? indicatorInactiveColor;

  /// Skip TextButton color. Defaults to [Theme.of(context).primaryColor].
  final Color? skipButtonColor;

  /// Next TextButton color. Defaults to [Theme.of(context).primaryColor].
  final Color? nextButtonColor;

  /// Shown while the stored "already seen" flag is being read.
  ///
  /// Defaults to a [CircularProgressIndicator]. It is on screen for one
  /// frame in the common case, and longer only on a slow first read.
  final Widget? loadingWidget;

  /// Whether this widget remembers, in [SharedPreferences], that the flow
  /// has been seen. Defaults to true.
  ///
  /// Set it to false to own that decision — to key the flag per account,
  /// say, or to keep it on a server. **Nothing else records it**: with
  /// this false and no storage of your own, the intro returns on every
  /// launch.
  /// Note: Handle the one time show logic yourself if you set this to false.
  final bool shouldUseDefaultStorage;

  @override
  State<FlutterOnBoarding> createState() => _FlutterOnBoardingState();
}

class _FlutterOnBoardingState extends State<FlutterOnBoarding> {
  /// The current page displayed in the onboarding flow. Defaults to 0.
  int currentPage = 0;

  /// The [PageController] used to control the scrolling of the onboarding flow.
  late PageController pageController;

  /// The [SharedPreferences] instance to read and write the flag with.
  ///
  /// Null lets the widget obtain its own.
  late SharedPreferences prefs;

  /// Whether the onboarding flow is loading. Defaults to true.
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    pageController = widget.pageController ?? PageController();

    if (widget.shouldUseDefaultStorage) {
      _initPrefs();
    } else {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _initPrefs() async {
    prefs = await SharedPreferences.getInstance();
    final isDone = prefs.getBool('isDone');

    if (isDone != null && isDone) {
      widget.onDone.call();
      return;
    }

    setState(() {
      isLoading = false;
    });
  }

  /// Records that the intro has been seen, so it is not shown again.
  Future<void> _setOnboardingDone() async {
    if (widget.shouldUseDefaultStorage) {
      await prefs.setBool('isDone', true);
    }
  }

  //dispose
  @override
  void dispose() {
    pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return isLoading
        ? widget.loadingWidget ??
            const Center(child: CircularProgressIndicator())
        : SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Stack(
                children: [
                  PageView.builder(
                    itemCount: widget.pages.length,
                    controller: pageController,
                    physics: widget.physics,
                    onPageChanged: (value) {
                      setState(() {
                        currentPage = value;
                      });
                    },
                    scrollDirection: widget.scrollDirection == Axis.vertical
                        ? Axis.vertical
                        : Axis.horizontal,
                    itemBuilder: (context, index) {
                      final isLastPage = index == widget.pages.length - 1;
                      final introModel = widget.pages[index];
                      return Column(
                        children: [
                          // image
                          _buildMainPageContent(introModel, context),

                          const SizedBox(height: 32),

                          if (widget.scrollDirection != Axis.vertical)
                            widget.indicator ?? _buildIndicators(),

                          // button
                          widget.navigationControl ??
                              _buildNavigationSection(
                                  isLastPage, context, index),
                          const SizedBox(height: 32),
                        ],
                      );
                    },
                  ),
                  if (widget.scrollDirection == Axis.vertical)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: widget.indicator ?? _buildIndicators(),
                    ),
                ],
              ),
            ),
          );
  }

  Expanded _buildMainPageContent(
    IntroModel introModel,
    BuildContext context,
  ) {
    return Expanded(
      child: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // image
                introModel.image,

                const SizedBox(height: 32),

                // title
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 16,
                    horizontal: 32,
                  ),
                  child: introModel.title,
                ),

                // description
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 16,
                    horizontal: 32,
                  ),
                  child: introModel.description,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavigationSection(
    bool isLastPage,
    BuildContext context,
    int index,
  ) {
    return Row(
      mainAxisAlignment:
          isLastPage ? MainAxisAlignment.end : MainAxisAlignment.spaceBetween,
      children: [
        if (!isLastPage)
          TextButton(
            onPressed: () {
              pageController.animateToPage(
                widget.pages.length - 1,
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeIn,
              );
            },
            child: Text(
              widget.skipButtonText ?? 'Skip',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: widget.skipButtonColor ?? Theme.of(context).primaryColor,
              ),
            ),
          ),
        CustomRoundedButton(
          color: widget.nextButtonColor ?? Theme.of(context).primaryColor,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: 16,
              horizontal: 32,
            ),
            child: Text(
              index == widget.pages.length - 1
                  ? widget.doneButtonText ?? 'Done'
                  : widget.nextButtonText ?? 'Next',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          onTap: () async {
            if (index == widget.pages.length - 1) {
              await _setOnboardingDone();
              widget.onDone.call();
            } else {
              unawaited(
                pageController.nextPage(
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeIn,
                ),
              );
            }
          },
        ),
      ],
    );
  }

  Widget _buildIndicators() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: DotsIndicator(
        dotsCount: widget.pages.length,
        position: currentPage,
        axis: widget.scrollDirection,
        decorator: DotsDecorator(
            activeShape: widget.activeIndicatorShape ??
                (const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(
                    Radius.circular(100),
                  ),
                )),
            activeSize: widget.activeIndicatorSize ??
                (widget.scrollDirection == Axis.vertical
                    ? const Size(9, 24)
                    : const Size(24, 9)),
            shape: widget.inactiveIndicatorShape ??
                (const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(
                    Radius.circular(100),
                  ),
                )),
            size: widget.inactiveIndicatorSize ?? const Size(9, 9),
            color: widget.indicatorInactiveColor ?? Colors.grey,
            activeColor:
                widget.indicatorActiveColor ?? Theme.of(context).primaryColor),
      ),
    );
  }
}
