# REVIEW: D2. Your dev team, on one floor inside Claude Code

99.74 s, 1920 x 1080, 30 fps, silent. Eleven sub-compositions mounted in `index.html`; 45 empty
`data-beat` markers set the review frames. Not rendered (the caller renders).

| Scene | Root time | Beat |
| --- | --- | --- |
| `s1` | 0.00-6.00 | the ask: You type the request; the pane folds into the floor; the office assembles; whole floor |
| `s2` | 6.00-18.90 | product corner: docs, three questions, answers typed and pinned as sticky notes, notebook line, spec.md |
| `s3` | 18.90-29.66 | whiteboard meeting: Sam explains, Morgan's question, spec + decisions updated, Priya photographs the journeys; engineers keep working |
| `s4` | 29.66-38.63 | the plan: Morgan draws workstreams + attack plan; engineers turn their chairs, roll up and watch; approval in the prompt bar; tickets handed out |
| `s5` | 38.63-52.13 | build: red then green tests, contract card, the guard, access_log card |
| `s6` | 52.13-64.04 | the lead's review: tests + 3 comments at his desk, he walks the row tagging Noah, Maya, Leo; fixes ticked; "Kai, try to break it." |
| `s7` | 64.04-74.34 | attack round at the security bench: 404 / 403 / own attacks blocked / 200 -> Finding High -> Ava fixes test-first -> 410 verified |
| `s8` | 74.34-85.34 | QA lab: Priya as Sara Lee, wrong refund total, bug walked to Morgan, Maya fixes, re-test, QA: PASS |
| `s9` | 85.34-92.44 | docs and memory in the library, a line in every notebook, the signoff board ticks |
| `s10` | 92.44-96.74 | whole floor again, the floor folds back into Claude Code, PR #42, Merge -> Merged |
| `s11` | 96.74-99.74 | end card |

## Creative calls

- **One floor, one camera, one clock.** The office is a 2:1 isometric diorama (14 x 10.5 m) drawn
  in flat colours with three-tone faces (light from the upper left) and flat shadows cast to the
  right. The back corner is cut by a wall that faces the camera; the whiteboard lives there, so the
  board is readable without shearing. Every other surface is in true iso: furniture is boxes with
  side faces, wall items (sticky notes, signoff board) are sheared onto their wall planes.
- **Every scene file builds the same master timeline** (absolute film seconds) and registers a
  scene timeline that tweens the master's time over its window. People, cards and the camera are
  therefore exactly where the last scene left them; the scene seams were snapshotted (-0.2 s to
  +0.2 s) and none jumps. The camera only glides (0.8-1.6 s) and the whole floor is seen at
  5.4-6.0 s and 93.1-93.9 s.
- **People face the camera at work, backs when they watch.** Engineers sit behind their desks with
  their monitor (ticket tab, code, test line) cheated to their screen-left so face and screen read
  together. For the plan they turn their chairs (a 2D squash turn into a back view), roll 1.4 m
  towards the board and watch from behind like an audience; tickets fly from Morgan to each of
  them; they roll back and turn to their screens.
- **Approval happens in Claude Code**: "Approve the plan?" appears in the prompt bar and you type
  "Yes." (truer to Plumbline than a bubble, and it keeps the plan uncovered).
- **Truth rules kept**: PR + you merge, no deploy; Morgan plans and reviews (monitor: "review: 3
  comments", with the code reviewer), Kai runs the attack round; Priya photographs product's
  journeys in the meeting and tests only after the build; HIPAA is labelled "DentEase rule";
  dummy names only; no model names.
- **Registry**: searched before building (isometric office, speech bubble, logo swing, typing,
  check mark, camera glide, character walk). Nothing covers an iso office or a character rig; the
  chat-message bubble timing and the pendulum-swing logo settle were inlined as in the first D.
- **Thumbnail** (frame 0): You at the home laptop with the Claude Code window open.

## Required steps, where they are

1. Product clarifies with you: s2 (bubbles + your typed answers -> sticky notes on the cork wall).
2. Whiteboard meeting: s3, Sam explains journeys + four criteria on the board; Morgan asks "Where do
   X-rays live?"; "Per-practice storage." -> blue line in the pinned spec.md + decisions.md card;
   Priya photographs the journeys ("Journeys saved. I'll test them later."). The engineers' heads
   and screens stay at the bottom of the frame, typing.
3. Sam and Priya walk back to their corners; Morgan draws the plan; the engineers turn, gather,
   watch; you approve; Morgan hands each a ticket: s3 end + s4.
4. Build test-first with collaboration: s5. Review with comments resolved: s6. Attack round: s7.
   QA with the bug walked to the lead: s8. Docs, notebooks, signoff: s9. PR and Merge: s10.

## What was measured

- `npx hyperframes check --json`: **ok, 0 errors** on the final pass. Earlier passes: the laptop
  lid of the hook painted over the terminal frame (stage got `z-index: 6`, home layer hidden after
  the push), the Merge/Merged swap and the PR under the end card (overlap marked, PR world hidden
  when the end card lands), the avatar crop (`data-layout-allow-overflow`).
- `npx hyperframes snapshot --review` twice (65 beat frames, 97 seam strips, phone sheets) plus six
  `--at` passes. A scratch layout checker also projected every bubble and card through the camera
  at its show time (on-screen box and px size); final run: 0 issues.
- Fixed from the frames:
  - P0: monitors' test lines were hidden behind their own desks, and Kai/Priya were drawn in front
    of their benches -> desks own the depth key, monitors sit at desk + 2, a person at their desk at
    desk - 5.
  - P0: the pane-to-floor fold was invisible (dark on dark, `skewX` missing from the tween
    defaults) -> default added, the pane warms to the floor colour as it folds, the iso grid shows.
  - P0: the attack-screen rows shared ids with the pane carets (two gold blocks on the PR frame,
    empty attack screen) -> renamed.
  - P0: the bug card covered Morgan's face while he spoke -> it shrinks into Priya's hand as she
    arrives, then flies to Maya's screen as a tag.
  - P1: Morgan sat behind the free-standing signoff board -> the board moved onto the right wall,
    sheared to the wall plane.
  - P1: the ending reached the whole floor only after everyone had vanished -> pull-out starts
    earlier, the floor holds 0.8 s with waves before it folds.
  - P1: board top and badges cropped in the meeting, bubbles cropped in the bench pairs, the bug,
    finding, docs and notebook cards off frame -> framings and card positions moved.
  - P1: spec.md and the review comments held too briefly -> +0.7 s each, paid for by trimming walks
    and the fold.
  - P2: a plant hid the plan's last workstream; Morgan's monitor code bars overlapped its text;
    stale props; Morgan's badge floating in Kai's shot without him (hidden while off frame).
- Only looked at, not measured: whether the back views read as "turned round to watch" at README
  size (in the sheets they do); the faces at the 0.255 overview are small by design.
- Nobody checked: the render, and any sound (silent on purpose).

## Warnings kept on purpose

- `film_silent`, `audio_none`: silent by request.
- `text_below_floor` (10): monitor ticket tabs (19-20 px) and screen text in wide or travelling
  shots; every read line is >= 30 px in its reading framing.
- `line_unread` (80): mostly world text passing during glides, and items that straddle a scene
  seam (the checker measures per scene, so a 2 s bubble split 1.6 s + 0.4 s reports twice). Real
  reads near the floor: spec.md's last AC and journeys line (1.7-1.9 s vs 1.95 s; the criteria are
  re-read on the board 3 s later), SEC-01-003 fail/pass (1.17 s vs 1.27 s).
- `contrast_aa_failure` (1): "DentEase" on Priya's idle screen while it fades in.
- `text_occluded` (info, 3): the spec card covering the sticky notes it absorbs; Morgan's bubble
  over the pinned spec card; the bug tag passing Ava's screen.
- `timeline_track_too_dense`, `composition_file_too_large`: structural (each scene carries the
  whole floor and the full timeline so seams stay exact).

## Weakest moment and what I'd change with more time

- **Docs and memory (s9, 85.3-92.4).** It reads, but the eight notebook lines are small spine
  marks and only Sam and Morgan are in the library; "everyone writes a line" is carried by a card
  and by people lifting notebooks you mostly see in passing. With more time: a short pan along the
  row as each person writes, each notebook showing one readable line.
- The plan's audience shot shows the engineers' backs behind their own monitors, so it can read as
  "they turned round at their desks" more than "they gathered".
- At phone width (360 px) bubbles and stamps read; board, screens and cards do not.

## Editing notes

- The scene files were written by a scratch generator (not kept in the repo; it lived in the
  session's temp folder). The HTML in `compositions/` is now the source; all eleven files share one
  world and one master script, so a change to a person, a timing or a card must be made in every
  scene file, or the generator rebuilt. Root windows live in `index.html` hosts and in each
  file's last lines (`stl.fromTo(tl, { time: START }, ...)`).
- Assets: `assets/floor.svg`, `grid.svg`, `shadows.svg`, `walls.svg`, `assets/props/*.svg`
  (furniture, depth-sorted by `z-index`), `assets/logo.png`.

## Render (when approved)

```sh
cd D:/Repos/plumbline/docs/media/plumbline-flow/d2-team-floor
npx hyperframes render --quality delivery --fps 30 --workers 2 --skill hyperframes -o renders/plumbline-flow-d2.mp4
```
