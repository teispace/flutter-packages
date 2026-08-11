## 0.0.1

- Editable flutter onboarding library.

## 0.0.2

- License Modified

## 0.0.3

- Author changed and bug fixes

## 0.0.4

- Bug fixes and License modified

## 0.0.5

- Bug fixes and License modified

## 0.0.6

- Bug fixes, Button modified and more understandable variables

## 0.0.7

- Screen Flickering Bug fixed, Custom Design to Get Started button added

## 0.0.8

- Bug fixed and Default Scroll Physics Changed to Bouncing Scroll Physics

## 0.0.9

- Bug fixed and Default Scroll Physics Changed to Bouncing Scroll Physics

## 1.0.0

- Bug fixed and Default Scroll Physics Changed to Bouncing,
- Page Indicator Added,
- SDK updated,
- Multidirection (Vertical & Horizontal) Support Added
- Option to enable or disable inbuilt one time onboarding visibility

## 1.0.1

- Issue during splash transition fixed

## 1.0.2

- Export optimized

## 1.0.3

- Export optimized

## 1.0.4

- Documentation Updated

## 1.0.5

- Documentation Updated

## 1.0.6

- Documentation Updated and Bug Fixed

## 2.0.0

Major because three things change for callers, all of them small.

**Breaking**

- `dots_indicator` moves to 4.x, whose `position` is a `double`. Only matters
  if you pass your own `indicator`.
- The minimum Dart SDK is 3.6.
- Removed `lib/widgets/flutter_onboarding.dart`, an older duplicate of the
  exported widget: never exported from the barrel and never imported, so
  importing it gave you a second copy of the same class. Use
  `package:flutter_onboarding/flutter_onboarding.dart`.

**Fixed**

- **A `PageController` you pass in is no longer disposed by this widget.** It
  belongs to you; disposing it left you holding one that threw on next use,
  and the error surfaced far from here.
- The stored flag is no longer read into a widget that has been disposed
  meanwhile — navigating away during the read threw.
- Three analysis errors from builders whose inferred `dynamic` return type
  could not be assigned to `List<Widget>`.

**Changed**

- The dots now follow a drag instead of jumping when it ends, and moving them
  no longer rebuilds every page. The indicator was the only thing reading the
  current page, so it now listens to the controller itself.
- No spinner at all when `shouldUseDefaultStorage` is false; there is nothing
  to wait for.
- The package's first tests, seven of them.
- Every public member documented — including a correction: **skip jumps to the
  last page rather than leaving the flow**, so `onDone` has exactly one caller.
- Moved into the `teispace/flutter-packages` monorepo.
