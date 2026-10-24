# API contract

Phase <phase>, module <module>.

## Where the schema lives
Name the single schema file for this feature (for example `openapi.yaml` in
this folder). Code and tests are checked against it, not the other way round.

## Versioning
State the version scheme and what counts as a breaking change. A breaking
change needs a new version, never an edit in place.

## Error format
One error shape for every endpoint: a status code, a stable machine code, a
human message and a request id. List the codes this feature adds.
