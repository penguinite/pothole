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
# api/nodeinfo.nim:
## This module contains all the routes that handle stuff related to the nodeinfo standard.

# From somewhere in Quark
import quark/[users, sessions, posts]

# From somewhere in Pothole
import pothole/[lib, conf, database]
import pothole/helpers/[routes, resp]

# From somewhere in the standard library
import std/[json]

# From nimble/other sources
import mummy

proc resolveNodeinfo*(req: Request) =
  
  configPool.withConnection cnf:
    respJson(
      $(%*{
        "links": [
          {
            "href": realURL(cnf) & "2.0",
            "rel":"http://nodeinfo.diaspora.software/ns/schema/2.0"
          }
        ]
      })
    )

  
proc nodeInfo2x0*(req: Request) =
  var totalSessions, totalValidSessions, totalUsers, totalPosts: int
  dbPool.withConnection db:
    totalSessions = db.getTotalSessions()
    totalValidSessions = db.getTotalValidSessions()
    totalUsers = db.getTotalLocalUsers()
    totalPosts = db.getNumTotalPosts()

  configPool.withConnection config:
    var protocols: seq[string] = @[]
    if config.getBoolOrDefault("instance", "federated", true):
      protocols.add("activitypub")
    
    respJson(
      $(%* {
        "version": "2.0",
        "software": {
          "name": "Pothole",
          "version": lib.phVersion,
        },
        "protocols": protocols,
        "services": {
          "inbound": [],
          "outbound": [],
        },
        "openRegistrations": config.getBoolOrDefault("user", "registrations_open", true),
        "usage": {
          "totalPosts": totalPosts,
          "users": {
            "activeHalfYear": totalSessions,
            "activeMonth": totalValidSessions,
            "total": totalUsers
          }
        },
        "metadata": {
          "nodeName": config.getString("instance", "uri"),
          "nodeDescription": config.getStringOrDefault("instance", "description", config.getStringOrDefault("instance", "summary", "")),
          "accountActivationRequired": config.getBoolOrDefault("user", "require_approval", false),
          "features": [
            "mastodon_api",
            "mastodon_api_streaming",
          ],
          "postFormats":[
            "text/plain",
            "text/html",
            "text/markdown",
            "text/x-rst"
          ],
        }
      })
    )
