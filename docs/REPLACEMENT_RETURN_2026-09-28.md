# Return to an earlier exercise

The replacement picker now admits compatible ancestors from the same replacement
slot, not arbitrary historical cards from other slots. It reuses the existing
record and never renames, deletes, merges, or re-keys performance logs.

Manual swaps retain matching primary regions, movement pattern and exercise family,
but do not require the same fatigue-derived anchor/secondary label. A new alternative
must still not increase the modeled shoulder/systemic/fatigue scores. This permits
the actual incline dumbbell → incline Smith example without changing generator rules.
Only Heavy Compound and Hypertrophy Compound share a family; other class boundaries
remain unchanged.

With no logged sets, A → B → A restores A's full outstanding work. With one set
logged on A and one on B from a three-set slot, returning gives A one saved set
plus one remaining set; B's performed set stays in replacement history.
Reusing a middle node rotates the historical chain to prevent ambiguous cycles.

Boundaries:
- Existing active duplicates, unresolved pain exclusions, finished sessions,
  and unrelated pending edits still prevent replacement.
- A skipped ancestor is not reactivated: doing so would erase its historical
  pain/equipment/time disposition. The picker explains this same-session limit.
- Sparse set-number histories and summary-only logs cannot be safely counted for
  a return; the transaction refuses with a specific explanation and no changes.
- A return may restore the original slot's higher modeled fatigue/risk, but this
  does not assert medical safety or relax future-planner substitution rules.
  Future preference is unavailable when those planner rules reject the reverse.
- An explicit supported future return clears conflicting source/target preferences.
  A today-only return leaves the owner's future preferences unchanged.

No schema, canonical key, or backup format changed. Model-level session resolution
is shared with the set logger, including program scoping and session-date handling.
Tests cover round trips, partial sets, repeated three-way swaps, persisted reload,
failed saves, preference behavior, skipped ancestors, and ambiguous log refusal.

## Owner check (existing workout; no API generation)

Before doing any sets, replace incline dumbbell press with incline Smith machine
press, reopen Replace, and select incline dumbbell press. Confirm one active card
and the same remaining-set budget, then reopen the app. During real training, if
you change exercises after performing sets, confirm each exercise retains its own
logged results and only the remaining work transfers. Do not enter fictional sets.
