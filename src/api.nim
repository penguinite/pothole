# Unused for now, but to be used for MastoAPI implementation later in the project
# This file could also include some definitions or procedures specifically intended for ActivityPub support
# Or we could move it to a new file called ap.nim

from std/json import JsonNode

type
  Actor* = object
    inbox*: string
    outbox*: string

type
  Activity* = object
    data*: JsonNode