import std/[tables, macros, json]
import mummy

proc createHeaders*(a: string): HttpHeaders =
  result["Content-Type"] = a
  return

macro respJsonError*(msg: string, code = 400, headers = createHeaders("application/json")) =
  var req = ident"req"

  result = quote do:
    `req`.respond(
      `code`, `headers`, $(%*{"error": `msg`})
    )
    return

macro respJson*(msg: string, code = 200, headers = createHeaders("application/json")) =
  var req = ident"req"

  result = quote do:
    `req`.respond(
      `code`, `headers`, `msg`
    )
    return