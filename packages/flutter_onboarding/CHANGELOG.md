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

## Unreleased

- **Breaking:** removed `lib/widgets/flutter_onboarding.dart`. It was an
  older duplicate of the exported widget — never exported from the barrel and
  never imported by anything, so importing it gave you a second copy of the
  same class. Anyone reaching past the barrel for it should import
  `package:flutter_onboarding/flutter_onboarding.dart` instead.
- Fixed three analysis errors caused by inferred `dynamic` return types on the
  widget's builders, which made them unassignable to `List<Widget>` under a
  strict analysis.
- Added the package's first tests, covering the one-time behaviour and the
  storage opt-out.
- Documented every public member, and corrected the docs for the skip button:
  it jumps to the last page rather than leaving the flow.
- Moved into the `teispace/flutter-packages` monorepo. SDK floor raised to
  3.6 to join its pub workspace.
