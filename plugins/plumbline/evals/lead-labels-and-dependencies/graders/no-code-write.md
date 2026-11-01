---
type: tool_used
tool: Write
# The lead never writes feature code. Its Writes are docs, plus what it owns and
# writes while planning since v0.6: contracts/, the database schema, migrations.
input_match: '"file_path":"(?![^"]*(?:docs[^"]{1,2}product|[/\\]contracts?[/.\\]|[/\\]migrations?[/\\]|[/\\]schema[.]))'
min: 0
max: 0
arm: both
---
