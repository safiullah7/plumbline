# Plumbline flow film D: your dev team, inside Claude Code

Picked by Safi on 2026-10-30. Replaces A–C and A1–A3 as the README film
(C is rejected; the others stay as references).

## The one thing

You have a whole dev team inside Claude Code. You ask for a feature; your
product engineer clarifies it with you, your lead plans it, senior engineers
build it test-first, the lead reviews and has it attacked, QA tests it like a
real user, bugs get fixed together, everything is documented and remembered,
and a PR arrives that you merge. Autonomous, collaborative, high quality.

## Example: DentEase (Safi's dental practice app, HIPAA-first, multi-practice)

The request, typed in Claude Code inside the DentEase project:
`/plumbline:build Patient portal: patients sign in and see their own X-rays, treatment plans and invoices`

Dummy names only (never real businesses): practices **Bright Smile Dental**
and **Riverside Dental**; patients **Emma Lee** (14) and her mother
**Sara Lee**.

## The team (names + specialty badges; no model names anywhere)

- **You**: the person who asks and, at the end, merges.
- **Sam · Product**: listens, researches, asks sharp questions, writes the spec.
- **Morgan · Lead**: seasoned, calm, sharp (silver at the temples, glasses, a
  board of clear diagrams); asks product the hard question, plans everything,
  reviews every piece of work, directs the attacks, signs off.
- **Maya · Backend**, **Leo · Frontend**, **Noah · Data**, **Ava · Imaging**:
  senior engineers; steady, reliable, trustworthy; sleeves up, test-first.
- **Kai · Security**: a senior engineer who didn't write this code and is
  sent in by the lead to break it (toolkit, stopwatch, a grin; playful).
- **Priya · QA**: tests the working feature like a real patient and parent
  (devices, checklist, sharp eye); files bugs, re-tests fixes.
- Every member keeps a notebook: Plumbline agents have project memory. The
  team library holds the docs they write.

## Beats (about 90 s)

1. **0–6 s, the ask.** Your laptop, a Claude Code window, the request typed.
   Enter. The terminal window swings open like the front of a doll's house:
   inside is a cut-away building, one room per role.
2. **6–20 s, product.** Sam reads DentEase's docs ("HIPAA-first",
   "multi-practice") and asks you, in bubbles you answer from your laptop:
   "Can a parent see a child's records?" — "Yes, until 18." "Are some notes
   private?" — "Internal notes stay hidden." "How long can an X-ray link
   live?" — "10 minutes." Sam writes spec.md, acceptance criteria
   (AC-01-001 Patients see only their own records · AC-01-002 Parents see a
   child's records until 18 · AC-01-003 Internal notes are never shown ·
   AC-01-004 X-ray download links expire after 10 minutes) and the journeys;
   a line goes into Sam's notebook. Triage stamp: `Security: independent`.
3. **20–32 s, lead.** Sam walks the spec upstairs. Morgan reads, asks Sam:
   "Where do X-rays live?" — "Per-practice storage." The spec and
   decisions.md update. Morgan draws the plan: four workstreams with tasks
   written test-first (unit + e2e), and in red the attack plan:
   SEC-01-001 Emma's ID swapped for another patient's → 404 ·
   SEC-01-002 Riverside staff open a Bright Smile patient → 403 ·
   SEC-01-003 an expired X-ray link reused → 410. "Approve the plan?" — you:
   "Yes." Tickets fly down to the workshop.
4. **32–48 s, engineers.** Each engineer gets a ticket; tests go red, then
   green (`AC-01-001: pass (2)`). They collaborate: Leo asks Maya "What does
   the records API return?" and a contract card slides over; Ava asks Noah
   for the access-log table. Leo reaches into backend code; the guard says
   "Maya owns backend/**" and Maya takes it.
5. **48–66 s, the lead's review.** Morgan runs the unit and e2e tests (all
   pass), then reviews the work with the code reviewer and pins comments:
   "N+1 query on the X-ray list: batch it" (performance), "Log every record
   view" (HIPAA rule), "Use the shared date formatter" (guidelines). The
   engineers fix each; Morgan re-checks and ticks. Then: "Kai, try to break
   it." Kai runs the plan's attacks and his own: other patient's X-ray →
   blocked; other practice → blocked; expired link → it still works from a
   cache: finding, High. Ava fixes it test-first; Kai re-tries → 410,
   verified.
6. **66–80 s, QA.** Priya tests the running feature like a parent: signs in
   as Sara, opens Emma's X-ray, plan, invoices. Bug: "Invoice total wrong
   after a refund." She files it, walks it to Morgan, Morgan assigns it to
   Maya, Maya fixes it, Priya re-tests: pass. Verdict: PASS.
7. **80–86 s, docs and memory.** The team library fills: spec, decisions,
   change log, test record; each notebook gets its line. Signoff checks tick:
   unit + e2e tests pass · attack tests pass · secrets scan clean ·
   0 open findings.
8. **86–90 s, hand-off.** The doll's house closes back into the terminal:
   `PR #42 Patient portal: own records — ready for your review`. Your cursor
   clicks Merge. End card: the logo, "Plumbline", "Your dev team, inside
   Claude Code".

## Truth rules (the film must not claim what Plumbline doesn't do)

- Plumbline opens a PR; you merge it. No deploys on screen.
- The lead plans the attacks and reviews (with the code reviewer); Kai, a
  senior engineer who didn't write the code, runs the attack round.
- Product's questions, the lead's question to product, the plan, tests
  first, review comments fixed, attack findings fixed and re-verified, QA bug
  reports fixed and re-tested, docs and memory: all real Plumbline behaviour.
- HIPAA is DentEase's requirement, not a Plumbline certification.

## Look

A dark Claude Code window that opens into a bright cut-away building (a
doll's house in the terminal): warm rooms, clear flat illustration, people
with faces and personality, speech bubbles in one clean style. Rooms:
product's study (sticky notes, research shelf), the lead's office (top
floor, diagram board), the engineers' workshop (four benches), the security
bench (Kai's toolkit), QA's lab (phones, tablet, laptop, checklist), the
team library (docs and notebooks). People walk the stairs to talk. One
accent for the request and the PR. The terminal frame stays as the outer
border most of the time, so it always reads "inside Claude Code".

## Revision 2 (Safi, after the first render): one 3D floor

The doll's-house cut-away (rooms stacked on floors) is replaced by **one open
floor in 3D (isometric, like a Sims-style office seen from above at an
angle)**, with a zone for each role, inside the Claude Code window frame:
- **The team area**: the four engineers' benches, the lead's desk and the big
  whiteboard are in the same room.
- **Product corner** (Sam: sticky-note wall, research shelf), **QA lab**
  (Priya: phones, tablet, laptop, test screen), **security bench** (Kai:
  toolkit, attack screen), **team library** (docs shelf and everyone's
  notebooks), and the **signoff board**.

Beat changes:
- After Sam's questions to you, **Sam, Morgan and Priya meet at the
  whiteboard**: Sam explains the feature on it (the journeys and the four
  criteria drawn up), Morgan asks "Where do X-rays live?", the answer is
  written up and the spec updates; Priya photographs the journeys she will
  test later (QA tests from product's journeys after the build; she does not
  plan). **Meanwhile the engineers keep working at their benches on other
  tickets.**
- When all is clear, **Sam and Priya go back to their corners**. Morgan
  draws the dev plan on the whiteboard (four workstreams, test-first, the
  attack plan in red). **The engineers turn their chairs, gather and watch**;
  Morgan hands each one a ticket. You approve the plan from the prompt bar.
- The rest follows the beats above, all on the same floor: build at the
  benches, the lead's review walking bench to bench with comments resolved,
  "Kai, try to break it" at the security bench, QA in the lab with the bug
  walked to Morgan, and docs and memory with people in it (Sam shelves the
  spec, Morgan files the decisions, everyone writes a line in their
  notebook), the signoff board ticking, then the PR and Merge.

Look: crisp isometric 3D with depth and shadows done in flat colours (no
blur or gradients), people with faces and personality drawn for the
isometric view, readable bubbles. It should look clearly better than the
first D: richer floor, furniture, plants, screens with real content.

## Format

About 90 s, 1920×1080, 30 fps, MP4 only (no GIF). Build silent; music and
light sound effects are an optional pass after Safi sees it.
