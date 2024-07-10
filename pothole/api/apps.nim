# Copyright © penguinite 2024 <penguinite@tuta.io>
#
# This file is part of Pothole.
# 
# Pothole is free software: you can redistribute it and/or modify it under the terms of
# the GNU Affero General Public License as published by the Free Software Foundation,
# either version 3 of the License, or (at your option) any later version.
# 
# Pothole is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License
# for more details.
# 
# You should have received a copy of the GNU Affero General Public License
# along with Pothole. If not, see <https://www.gnu.org/licenses/>. 
# api/ph.nim:
## This module contains all the routes for the ph method in the api

# From somewhere in Pothole
import pothole/[database, routeutils]

# From somewhere in the standard library
import std/[json, strutils]

# From nimble/other sources
import mummy

proc hasValidStrKey(j: JsonNode, k: string): bool =
  if not j.hasKey(k):
    return false

  if j[k].kind != JString:
    return false

  try:
    if j[k].getStr().isEmptyOrWhitespace():
      return false
  except:
    return false

  return true



proc v1Apps*(req: Request) =
  # This is a big, complex API route as it needs to handle 3 different data form submission methods.
  var headers: HttpHeaders
  headers["Content-Type"] = "application/json"

  # Check if the request matches anything we support.
  # What we do support is the following:
  # Typical form submissions: x-www-form-urlencoded
  # Typical multipart: multipart/form-data
  # JSON via request body: application/json
  var contentType = "application/x-www-form-urlencoded"
  if req.headers.contains("Content-Type"):
    contentType = req.headers["Content-Type"]

  case contentType:
  of "application/x-www-form-urlencoded", "multipart/form-data", "application/json":
    discard
  else:
    # Throw an error if the format of the message can't be understood
    req.respond(
      401,
      headers,
      $(%*{"error": "Couldn't process request!"})
    )
  

  var result: JsonNode

  # First, Check if client_name and redirect_uris exist.
  # If not, then error out.
  var
    client_name, website, req_scopes = ""

    # TODO: What does one do with this???
    # The API docs suggest that we should parse and see if its an absolute uri.
    # Throwing an error if it isn't... But like, what's the point of this anyway???
    redirect_uris = ""
  
  case contentType:
  of "application/x-www-form-urlencoded":
    var fm = req.unrollForm()
    if not fm.isValidFormParam("client_name") or not fm.isValidFormParam("redirect_uris"):
      req.respond(401, headers, $(%*{"error": "Missing required parameters."}))
      return

    # Get the website if it exists
    if fm.isValidFormParam("website"):
      website = fm.getFormParam("website")
    
    # Get the scopes if they exist
    if fm.isValidFormParam("scopes"):
      req_scopes = fm.getFormParam("scopes")

    # Finally, get the stuff we need.
    client_name = fm.getFormParam("client_name")
    redirect_uris = fm.getFormParam("redirect_uris")
  of "multipart/form-data":
    var mp = req.unrollMultipart()

    # Check if the required stuff is there
    if not mp.isValidMultipartParam("client_name") or not mp.isValidMultipartParam("redirect_uris"):
      req.respond(401, headers, $(%*{"error": "Missing required parameters."}))
      return
  
    # Get the website if it exists
    if mp.isValidMultipartParam("website"):
      website = mp.getMultipartParam("website")
    
    # Get the scopes if they exist
    if mp.isValidMultipartParam("scopes"):
      req_scopes = mp.getMultipartParam("scopes")

    # Finally, get the stuff we need.
    client_name = mp.getMultipartParam("client_name")
    redirect_uris = mp.getMultipartParam("redirect_uris")
  of "application/json":
    var json: JsonNode = newJNull()
    try:
      json = parseJSON(req.body)
    except:
      req.respond(401, headers, $(%*{"error": "Invalid JSON."}))
      return

    # Double check if the parsed JSON is *actually* valid.
    if json.kind == JNull:
      req.respond(401, headers, $(%*{"error": "Invalid JSON."}))
      return
    
    # Check if the required stuff is there
    if not json.hasValidStrKey("client_name") or not json.hasValidStrKey("redirect_uris"):
      req.respond(401, headers, $(%*{"error": "Missing required parameters."}))
      return

    # Get the website if it exists
    if json.hasValidStrKey("website"):
      website = json["website"].getStr()

    # Get the scopes if they exist
    if json.hasValidStrKey("scopes"):
      req_scopes = json["scopes"].getStr()
    
    # Finally, get the stuff we need.
    client_name = json["client_name"].getStr()
    redirect_uris = json["redirect_uris"].getStr()
  else:
    return

  # Parse scopes
  var scopes = "read"
  if req_scopes != scopes:
    for scope in req_scopes.split(" "):
      if not scope.verifyScope():
        req.respond(401, headers, $(%*{"error": "Invalid scope: " & escape(scope)}))
        return
    scopes = req_scopes
  
  var client_id, client_secret: string
  dbPool.withConnection db:
    client_id = db.createClient(
      client_name,
      website,
      scopes
    )
    client_secret = db.getClientSecret(client_id)
  
  result = %* {
    "id": client_id,
    "name": client_name,
    "website": website,
    "redirect_uri": redirect_uris,
    "client_id": client_id,
    "client_secret": client_secret,
    "scopes": scopes.split(" ") # Undocumented.
  }

  req.respond(200, headers, $(result))

  
proc v1AppsVerify*(req: Request) = 
  var headers: HttpHeaders
  headers["Content-Type"] = "application/json"
  var result = %* {}
  req.respond(200, headers, $(result))