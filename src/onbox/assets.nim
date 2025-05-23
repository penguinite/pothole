# Copyright © penguinite 2024-2025 <penguinite@tuta.io>
# Copyright © Leo Gavilieau 2022-2023 <xmoo@privacyrequired.com>
#
# This file is part of Onbox.
# 
# Onbox is free software: you can redistribute it and/or modify it under the terms of
# the GNU Affero General Public License as published by the Free Software Foundation,
# either version 3 of the License, or (at your option) any later version.
# 
# Onbox is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License
# for more details.
# 
# You should have received a copy of the GNU Affero General Public License
# along with Onbox. If not, see <https://www.gnu.org/licenses/>. 
#
# assets.nim:
## This module basically acts as the assets store
import std/tables, iniplus, routes, temple

proc getBuiltinAsset*(fn: string): string =
  # Get static asset
  const table = {
    "oauth.html": staticRead("../assets/oauth.html"),
    "signin.html": staticRead("../assets/signin.html"),
    "generic.html": staticRead("../assets/generic.html"),
    "home.html": staticRead("../assets/home.html"),
    "style.css": staticRead("../assets/style.css")
  }.toTable
  return table[fn]

proc getAvatar*(config: ConfigTable, user_id: string): string =
  ## When given a user's ID, return a URL to their avatar.
  case config.getString("storage", "type"):
  of "flat":
    # Simply find the file in the filesystem and return a public link to it.

    # If `upload_uri` has been configured, then we'll use it as a base
    # Otherwise we'll use realURL() + /media/
    if config.exists("storage", "upload_uri"):
      return config.getString("storage", "upload_uri") & "user/" & user_id & "/avatar.webp"
    else:
      return config.realURL() & "media/user/" & user_id & "/avatar.webp"

  of "pony":
    # "pony" is a media pooling feature, similar in spirit to Jortage.
    # This is an experimental feature as no reliable server exists for this
    # kinda thing yet...
    raise newException(
      CatchableError,
      "Pony pooling!(tm) Coming sooner or later, eventually..."
    )
  of "remote":
    # TODO: Finish S3 compatability
    raise newException(
      CatchableError,
      "S3 storage: Not implemented yet, sorry."
    )
  else:
    raise newException(
      CatchableError,
      "Unknown media storage type: " & config.getString("storage", "type")
    )

proc getHeader*(config: ConfigTable, user_id: string): string =
  ## When given a user's ID, return a URL to their avatar.
  case config.getString("storage", "type"):
  of "flat":
    # Simply find the file in the filesystem and return a public link to it.

    # If `upload_uri` has been configured, then we'll use it as a base
    # Otherwise we'll use realURL() + /media/
    if config.exists("storage", "upload_uri"):
      return config.getString("storage", "upload_uri") & "user/" & user_id & "/header.webp"
    else:
      return config.realURL() & "media/user/" & user_id & "/header.webp"
  of "pony":
    # "pony" is a media pooling feature, similar in spirit to Jortage.
    # This is an experimental feature as no reliable server exists for this
    # kinda thing yet...
    raise newException(
      CatchableError,
      "Pony pooling!(tm) Coming sooner or later, eventually..."
    )
  of "remote":
    # TODO: Finish S3 compatability
    raise newException(
      CatchableError,
      "S3 storage: Not implemented yet, sorry."
    )
  else:
    raise newException(
      CatchableError,
      "Unknown media storage type: " & config.getString("storage", "type")
    )

proc templateWithAsset*(asset: string, data: Table[string, string] = initTable[string, string]()): string =
  templateify(
    getBuiltinAsset(asset),
    data, @[] # No attributes...
  )