## Mobile design rules
Applies to the feature's mobile-ui surfaces. The Screen inventory above stays the single list
of screens.

### Device sizes
Mock and check every key screen at 390x844 and 430x932. Add a tablet size only
if the spec needs one. Respect safe areas and the on-screen keyboard.

### Platform conventions
Follow iOS and Android conventions for navigation, back behaviour, system
dialogs and controls. Note any place the two platforms deliberately differ.

### Gestures
List each gesture (swipe, long press, pull to refresh) and its visible
alternative. No action may depend on a gesture alone.

### Offline and permission states
For each screen: offline, flaky network, and permission denied or not yet asked.
Say what the user sees and how they recover.

### Accessibility checklist
Fill qa/a11y-checklist.tsv with one row per check, tab separated:
`screen<TAB>width<TAB>check<TAB>result<TAB>impact<TAB>evidence`
- result: pass or fail
- impact: critical, serious, moderate or minor
- checks to cover: touch target size, labels for screen readers, focus order,
  text scaling, contrast, reduced motion
