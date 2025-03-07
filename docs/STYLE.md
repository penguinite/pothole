
# Database logic should not have checks or excessive queries.

The procedures in `src/pothole/db` should do *one thing only* without **any** checks.

These procedures are meant to be a simple abstraction over the raw database,
we don't want procedures to excessively call other procedures because then
it can be hard to trace and profile where queries are actually coming from.

And yes, this means absolutely no checks. The API layer should be doing checks

# The entities module shouldn't use dbPool or configPool

The entities module is honestly horrible,
the thought behind it (re-using existing code for new API methods) isn't bad but
it has now become a mess calling dbPool everywhere.
