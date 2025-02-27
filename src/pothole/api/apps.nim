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
# api/apps.nim:
## This module contains all the routes for the apps method in the mastodon api

# From somewhere in Quark
import quark/[apps, oauth]

# From somewhere in Pothole
import pothole/[database]

# Helper procs
import pothole/helpers/[req, resp, routes]

# From somewhere in the standard library
import std/[json, strutils]

# From nimble/other sources
import mummy

proc v1Apps*(req: Request) =
  # This is a big, complex API route as it needs to handle 3 different data form submission methods.
  var headers: HttpHeaders
  headers["Content-Type"] = "application/json"

  # Check if the request matches anything we support.
  # What we do support is the following:
  # Typical form submissions: x-www-form-urlencoded
  # Typical multipart: multipart/form-data
  # JSON via request body: application/json
  var contentType = req.getContentType()

  var result: JsonNode

  # First, Check if client_name and redirect_uris exist.
  # If not, then error out.
  var
    client_name, website, req_scopes = ""

    # The API docs suggest that we should parse and see if its an absolute uri.
    # Throwing an error if it isn't... But like, what's the point of this anyway???
    redirect_uris = ""
  
  case contentType:
  of "application/x-www-form-urlencoded":
    var fm = req.unrollForm()
    if not fm.formParamExists("client_name") or not fm.formParamExists("redirect_uris"):
      respJsonError("Missing required parameters.")

    # Get the website if it exists
    if fm.formParamExists("website"):
      website = fm["website"]
    
    # Get the scopes if they exist
    if fm.formParamExists("scopes"):
      req_scopes = fm["scopes"]

    # Finally, get the stuff we need.
    client_name = fm["client_name"]
    redirect_uris = fm["redirect_uris"]
  of "multipart/form-data":
    var mp = req.unrollMultipart()

    # Check if the required stuff is there
    if not mp.multipartParamExists("client_name") or not mp.multipartParamExists("redirect_uris"):
      respJsonError("Missing required parameters.")
  
    # Get the website if it exists
    if mp.multipartParamExists("website"):
      website = mp["website"]
    
    # Get the scopes if they exist
    if mp.multipartParamExists("scopes"):
      req_scopes = mp["scopes"]

    # Finally, get the stuff we need.
    client_name = mp["client_name"]
    redirect_uris = mp["redirect_uris"]
  of "application/json":
    var json: JsonNode = newJNull()
    try:
      json = parseJSON(req.body)
    except:
      respJsonError("Invalid JSON.")

    # Double check if the parsed JSON is *actually* valid.
    if json.kind == JNull:
      respJsonError("Invalid JSON.")
    
    # Check if the required stuff is there
    if not json.hasValidStrKey("client_name") or not json.hasValidStrKey("redirect_uris"):
      respJsonError("Missing required parameters.")

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
    respJsonError("Unknown Content-Type.")

  # Parse scopes
  var scopes = "read"
  if req_scopes != scopes:
    for scope in req_scopes.split(" "):
      if not scope.verifyScope():
        respJsonError("Invalid scope: " & scope)
    scopes = req_scopes
  
  var client_id, client_secret: string
  dbPool.withConnection db:
    client_id = db.createClient(
      client_name,
      website,
      scopes,
      redirect_uris
    )
    client_secret = db.getClientSecret(client_id)
  
  result = %* {
    "id": client_id,
    "name": client_name,
    "website": website,
    "redirect_uri": redirect_uris,
    "client_id": client_id,
    "client_secret": client_secret,
    "scopes": scopes.split(" ") # Non-standard: Undocumented.
  }

  req.respond(200, headers, $(result))

  
proc v1AppsVerify*(req: Request) = 
  var headers: HttpHeaders
  headers["Content-Type"] = "application/json"

  if not req.authHeaderExists():
    respJsonError("The access token is invalid")
  
  let token = req.getAuthHeader()
  var name, website = ""

  dbPool.withConnection db:
    if not db.tokenExists(token):
      respJsonError("The access token is invalid")
    
    let id = db.getTokenApp(token)
    name = db.getClientName(id)
    website = db.getClientLink(id)

  var result = %* {
    "name": name,
    "website": website,
  }
  req.respond(200, headers, $(result))
