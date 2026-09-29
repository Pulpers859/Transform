# Empty replacement picker — investigation checkpoint

Owner reports that replacement choices disappeared on unfinished and future
workouts after 1c602b5, with 0c0b4aa working. Screenshot shows Reverse Pec Deck.
Treat this as an unresolved device regression, not disproven by passing tests.

Scoped comparison found that the new candidate predicate admits a superset of
the former choices for identical model/catalog state. Session guards, exclusions,
and catalog lookup were unchanged. This does not explain the device behavior.

This checkpoint does NOT claim a root-cause fix. It replaces the generic empty
message with R2 diagnostics identifying missing day links, archived programs,
rated/closed/date-blocked sessions, unknown names, or counts surviving the
compatibility/day/pain filters. No history or safety restriction is relaxed.

Regression coverage explicitly exercises Reverse Pec Deck on future/unstarted
and active unfinished days, and compares live choices against the 0c0b4aa
predicate across the catalog. Device evidence is still required: open the same
empty picker and send the entire R2 message. No generation or logged test sets
are required.
