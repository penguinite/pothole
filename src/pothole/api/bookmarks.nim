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
# api/bookmarks.nim:
## This module contains all the routes for the bookmarks method in the mastodon api.

# From somewhere in Pothole
import quark/[apps, oauth, auth_codes, bookmarks]
import pothole/[database, conf]
import pothole/helpers/[entities, req, resp, routes]
from std/strutils import parseInt

# From somewhere in the standard library
import std/json

# From nimble/other sources
import mummy

proc bookmarksGet*(req: Request) =
  var headers: HttpHeaders
  headers["Content-Type"] = "application/json"
  if not req.authHeaderExists():
    respJsonError("This API requires an authenticated user", 401)
      
  let token = req.getAuthHeader()
  var user = ""
  dbPool.withConnection db:
    # Check if the token exists in the db
    if not db.tokenExists(token):
      respJsonError("This API requires an authenticated user", 401)
        
    # Check if the token has a user attached
    if not db.tokenUsesCode(token):
      respJsonError("This API requires an authenticated user", 401)
        
    # Double-check the auth code used.
    if not db.authCodeValid(db.getTokenCode(token)):
      respJsonError("This API requires an authenticated user", 401)
    
    # Check if the client registered to the token
    # has a public oauth scope.
    if not db.hasScope(db.getTokenApp(token), "read:bookmarks"):
      respJsonError("This API requires an authenticated user", 401)

    user = db.getTokenUser(token)

  var
    limit = 20
    result: JsonNode = newJArray()
  
  if req.queryParams.contains("limit"):
    try:
      limit = parseInt(req.queryParams["limit"])
    except:
      limit = 20

  ## TODO: Implement pagination with min_id, max_id and since_id
  dbPool.withConnection db:
    for id in db.getBookmarks(user, limit):
      result.elems.add(status(id))
  req.respond(200, headers, $(result))
