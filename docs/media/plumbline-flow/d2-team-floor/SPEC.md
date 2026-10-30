# SPEC: D2. Your dev team, on one floor inside Claude Code

Brief: `../STORYLINE-D.md`, section "Revision 2 (Safi, after the first render): one 3D floor"
(overrides the doll's house). Beats, dialogue, labels and the truth rules come from the first D
(`../d-team-inside-claude/SPEC.md`), re-staged on one open isometric floor.

GOAL:    the viewer watches one request turn the Claude Code window into one open office floor,
         follows every hand-off on that floor (product's questions, the whiteboard meeting, the
         plan the engineers turn round to watch, test-first build, the lead's review, Kai's attack
         round, QA, docs and memory, signoff) and sees a PR come back that they merge.
OUTPUT:  HyperFrames, 1920 x 1080, 30 fps, silent (music/SFX optional later). MP4 only.
TIME:    99.74 s x 30 = 2992 frames. No music, so no beat grid; something new every 1.5-3 s.

LOOK:    medium = a flat-colour isometric diorama (2:1 dimetric) on the navy ground of the
         Claude Code window. Projection: X = (x - y) * 224, Y = (x + y) * 112 - z * 274.3 (world px,
         1 m = 224 px along an axis, 274 px of height). One floor 14 x 10.5 m, back corner cut by a
         diagonal wall (chamfer at x + y = 4.5) that faces the camera and carries the whiteboard,
         so the board is the one big readable wall.
         Light from the upper left: tops full colour, +y faces x0.90, +x faces x0.76; flat shadows
         cast to the right (+x 0.42 h, -y 0.14 h) as one #3A2A1A fill at 13% opacity. No blur,
         gradients, glow, grain or particles (hazard stripes on the guard sign are hard stops).
         Terminal frame (screen space, always on): ground #1A2238, title bar "DentEase · Claude Code"
         (Nunito 700 30 px #AEB7CF), viewport 1864 x 920 at (28, 64), prompt bar with your face,
         gold "›" and your typed answers (JetBrains Mono 700 40 px). Outside the room: #141B2E with an
         iso grid of #1D2640 lines (the floor of the terminal).
         Floor: oak #E9D6B6 with plank lines #DDC6A0; slab edges #B4865A / #946A42. Walls: right
         #F3EEE5 (lit), chamfer #E7E0D3, left #D9D1C3. Zone floors: lead rug #D5DCEC (hexagon
         parallel to the board), engineer rugs #E6DACB, product rug #C5E5DE, security rug #F2D7E5,
         QA tiles #DCEDF2, lounge rug #EBCFB8, library round rug #E6EED8.
         Ink #1E2433. Gold #E8C26A only on the request, the PR card and the end card.
         Pass #2E9E5B / #5FD08A on screens, fail #D9473B / #FF7A6E. Review notes #F2C46B.
         Type (world px, read at the framing given in SHOTS so nothing read is under 30 px on screen
         and no bubble under 40 px): bubbles Nunito 800 52; badges Nunito 800 36; cards 38-42;
         whiteboard 36-48; signoff 33-40; monitor test lines JetBrains Mono 700 29-30 (read at >= 1.05).
OBJECTS: zones on one floor (screen position in the overview):
         - whiteboard on the chamfer wall (top centre), lead rug in front of it;
         - engineers' row: four desks in one screen-horizontal row under the board
           (Leo, Maya, Noah, Ava), each with a drawer pedestal, keyboard, mug, a personal prop
           (sticky notes, rubber duck, books, X-ray light pad) and a frontal monitor at the
           person's left showing a ticket tab, code bars and the test line;
         - Morgan's desk on the right wall (lamp, books, review monitor), poster and clock above;
         - signoff board on the right wall (sheared to the wall plane), Kai's security bench next
           to it (pegboard of tools, server rack, red toolbox, attack screen 1.6 m);
         - product corner front left (Sam's standing desk, cork wall with sticky notes, research
           shelf with a globe), team library on the left wall (bookcase, docs row, eight
           notebooks in each person's colour, reading table);
         - QA lab front right on tiles (bench with phone, tablet, laptop, test screen running
           DentEase as Sara Lee, device cabinet), lounge front centre (sofa, coffee table, lamp),
           seven floor plants, water cooler, window with a skyline.
         People: the first D cast (same names, colours and props), redrawn with a front view and a
         back view (hair from behind, hood, collar), seated and standing legs, right-side shading,
         hands, shoes, 3/4 face offset; Morgan x1.05 with silver temples, glasses and beard;
         Kai's cap, grin and stopwatch; Priya's braid and raised brow; Leo's freckles and
         headphones; Noah's beanie and beard; Ava's long hair; Maya's curls and flannel.
         Each carries a name badge "Name · Role" that travels with them. Chairs roll with them.
MOTION:  one paused master timeline (absolute film seconds) is built identically in every scene
         file; each scene's registered timeline tweens the master's time over its window, so every
         seam is continuous by construction. Camera = zoom wrapper (origin 932,460) over a pan
         layer; glides power2.inOut 0.8-1.6 s, never a hard cut on the floor. Bubbles: registry
         chat-message timing (0.75 -> 1, 0.12 s). Walks 2.5-3.8 m/s with leg swing, 8 px bob, depth
         re-sorted every 0.15 s. Turns: squash scaleX to 0.12 in 0.1 s, swap front/back, open out
         back.out(1.6). Floor assembly: pane folds into the floor (affine to the floor diamond,
         0.9 s power3.inOut), walls drop 0.5 s, 36 props drop in depth order over 0.9 s
         (power3.out), people pop back.out(1.8). End: the reverse, then PR, Merge, the logo on the
         registry pendulum-swing settle.
SHOTS (root seconds; framing = centre X, Y, scale):
  s1   0.00-6.00   You type the request at home; push into the laptop; Enter; the pane folds into
                   the floor; the office assembles; whole floor at 0.255; Sam waves.
  s2   6.00-18.90  Product corner (1800,2110,0.8): Sam reads DentEase docs (HIPAA-first,
                   multi-practice), three questions, your typed answers become sticky notes on the
                   cork wall, a line in her notebook, spec.md with AC-01-001..004, journeys,
                   "Security: independent".
  s3  18.90-29.66  Whiteboard meeting (3240,1672,0.86; the engineers' heads and screens keep
                   working along the bottom): Sam pins spec.md, draws journeys and four criteria;
                   Morgan: "Where do X-rays live?" Sam: "Per-practice storage." -> spec line +
                   decisions.md; Priya photographs the journeys: "Journeys saved. I'll test them
                   later."; Sam and Priya go back to their corners.
  s4  29.66-38.63  Morgan wipes the board and draws the plan (four workstreams, tests first,
                   attack plan in red); the four engineers turn their chairs, roll up and watch from
                   behind; "Approve the plan?" / "Yes." in the prompt bar; Morgan hands each a ticket;
                   they roll back.
  s5  38.63-52.13  Benches (2420,2185,1.05) then (3680,2185,1.05): red then green tests; Leo asks
                   Maya, contract card; the guard "Maya owns backend/**", "I'll take it."; Ava asks
                   Noah, "Coming up.", access_log card.
  s6  52.13-64.04  Morgan's desk (5050,2110,1.2): unit + e2e pass, review: 3 comments, the three
                   comments read; he walks the row (0.92) tagging Noah, Maya, Leo; each fixes, the tag
                   turns into a tick; "Kai, try to break it."
  s7  64.04-74.34  Security bench (5640,2530,1.2): "With pleasure."; 404, 403, own attacks
                   blocked, SEC-01-003 -> 200; Finding · High flies to Ava (3950,2200,1.05), red then
                   green; back to Kai: 410, verified, thumbs up.
  s8  74.34-85.34  QA lab (4560,3060,1.1): Priya as Sara Lee, X-rays, plan, invoices, wrong total
                   ringed, Bug card; she walks it to Morgan (3975,2170,0.78): "Maya, this one's
                   yours." / "On it."; refund total red then green; re-test $80, QA: PASS.
  s9  85.34-92.44  Library (2120,1720,1.0): Sam shelves spec.md, Morgan files decisions.md, change
                   log and test record land; everyone writes a line in their notebook (eight
                   notebook spines get a line); signoff board (5574,2015,1.25) ticks four checks.
  s10 92.44-96.74  Pull out to the whole floor, everyone looks up, three wave; the floor folds back
                   into the terminal pane; PR #42 card; your cursor clicks Merge; Merged.
  s11 96.74-99.74  End card: logo swings to rest, "Plumbline", "Your dev team, inside Claude Code".
BANNED:  model names; deploy/ship/live/production words; real business names; role-handle names;
         dark void with small floating things (the floor fills the height in wide shots);
         glow, bloom, particles, grain, blur, motion blur, gradients; glass cards; serif display,
         italic accent words, "01/02" labels, pill chips; everything fading and sliding up; text
         moving while read; corner labels, HUD readouts; three cards in a row; the logo before
         the end card; gold outside request/PR/end card; a face or read word cropped in a hold;
         a card over a speaker's face; HIPAA as a Plumbline certification; a stacked doll's house
         (D1's look); hard cuts between zones; furniture drawn flat-on without side faces
         (only the board wall, monitors and cards face the camera).
QA:      the 45 data-beat markers in index.html are the review frames; scene seams at 6.00,
         18.90, 29.66, 38.63, 52.13, 64.04, 74.34, 85.34, 92.44, 96.74.
