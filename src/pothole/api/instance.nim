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
# api/instance.nim:
## This module contains all the routes for the instance method in the api

# From somewhere in Pothole
import pothole/helpers/entities

# From somewhere in the standard library
import std/[json]

# From nimble/other sources
import mummy

proc v1InstanceView*(req: Request) = 
  var headers: HttpHeaders
  headers["Content-Type"] = "application/json"
  req.respond(200, headers, $(v1Instance()))

proc v2InstanceView*(req: Request) = 
  var headers: HttpHeaders
  headers["Content-Type"] = "application/json"
  req.respond(200, headers, $(v2Instance()))

proc v1InstanceExtendedDescription*(req: Request) =
  var headers: HttpHeaders
  headers["Content-Type"] = "application/json"
  req.respond(200, headers, $(extendedDescription()))

proc v1InstanceRules*(req: Request) =
  var headers: HttpHeaders
  headers["Content-Type"] = "application/json"
  req.respond(200, headers, $(rules()))

# MISSING: [
# /api/v1/instance/translation_languages
# /api/v1/instance/domain_blocks
# /api/v1/instance/activity
# /api/v1/instance/peers
# ]