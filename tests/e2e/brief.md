# Product brief: Treatment rooms

The clinic app is used by several clinics; each clinic is a separate tenant and
must never see another's data. Auth is simulated by the X-User header
({"clinicId": "...", "role": "admin" | "receptionist"}).

## What the user wants in phase 01
Clinic admins set up the treatment rooms their clinic has, so a later phase can
book appointments into rooms. Receptionists see the list.

- Admins add a room (name, optional description), rename it, deactivate it and
  reactivate it. Rooms are never deleted.
- Receptionists only view. The list shows active rooms first, then inactive.
- Room names are unique per clinic, case-insensitive, 1-60 characters.
- At most 50 rooms per clinic, active or inactive.

## Answers the user has already given
Use these instead of asking; they are the user's decisions.
- An admin may deactivate the last active room, but sees a warning first:
  "This is your last active room. Patients can't be booked until you add or
  reactivate one."
- Deactivating needs no reason.
- Inactive rooms are shown greyed out with an "Inactive" badge, not hidden.
- Success metric: an admin can set up 10 rooms in under 3 minutes.
- Out of scope: booking, room opening hours, room photos.

If a question comes up that these don't answer, pick the option you'd recommend,
log it in questions.md as ANSWERED with "decided from brief" as the answer's
source, and carry on. Don't escalate: the user isn't available during this run.
