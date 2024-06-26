# Copyright © Leo Gavilieau 2022-2023 <xmoo@privacyrequired.com>
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

# From somewhere in Quark
import quark/strextra

# From somewhere in Pothole
import pothole/[conf, database, lib]

# From somewhere in the standard library
import std/[tables, options]

# From nimble/other sources
import mummy, mummy/multipart

proc prepareTable*(db: DbConn, config: ConfigTable): Table[string, string] =
  ## Creates a table that can be passed onto temple.templateify with all the data we usually need.
  result = {
    "name": config.getString("instance","name"), # Instance name
    "description": config.getString("instance","description"), # Instance description
    "sign_in": config.getStringOrDefault("web","_signin_link", "/auth/sign_in/"), # Sign in link
    "sign_up": config.getStringOrDefault("web","_signup_link", "/auth/sign_up/"), # Sign up link
  }.toTable

  # Instance staff (Any user with the admin attribute)
  if config.exists("web","show_staff") and config.getBool("web","show_staff") == true:
    # Build a list of admins, by using data from the database.
    result["staff"] = ""
    for user in db.getAdmins():
      result["staff"].add("<li><a href=\"/users/" & user & "\">" & user & "</a></li>") # Add every admin as a list item.

  # Instance rules (From config)
  if config.exists("instance","rules"):
    # Build the list, item by item using data from the config file.
    result["rules"] = ""
    for rule in config.getStringArray("instance","rules"):
      result["rules"].add("<li>" & rule & "</li>")

  # Pothole version
  when not defined(phPrivate):
    if config.getBool("web","show_version"):
      result["version"] = lib.phVersion
  return result

proc isValidQueryParam*(req: Request, query: string): bool =
  ## Check if a query parameter (such as "?query=parameter") is valid and not empty
  return not req.queryParams[query].isEmptyOrWhitespace()

proc getQueryParam*(req: Request, query: string): string =
  ## Returns a query parameter (such as "?query=parameter")
  return req.queryParams[query]

proc isValidPathParam*(req: Request, path: string): bool =
  ## Checks if a path parameter such as /users/{user} is valid and not empty
  return not req.pathParams[path].isEmptyOrWhitespace()

proc getPathParam*(req: Request, path: string): string =
  ## Returns a path parameter such as /users/{user}
  return req.pathParams[path]

type
  MultipartEntries* = Table[string, string]

proc unrollMultipart*(req: Request): MultipartEntries =
  ## Unrolls a Mummy multipart data thing into a table of strings.
  ## which is way easier to handle.
  for entry in req.decodeMultipart():
    if entry.data.isNone():
      continue
    
    let
      (start, last) = entry.data.get()
      val = req.body[start .. last]

    if val.isEmptyOrWhitespace():
      continue

    result[entry.name] = val
    
  return result

proc isValidFormParam*(mp: MultipartEntries, param: string): bool =
  ## Returns a parameter submitted via a HTML form
  return mp.hasKey(param) and not mp[param].isEmptyOrWhitespace()

proc getFormParam*(mp: MultipartEntries, param: string): string =
  ## Checks if a parameter submitted via an HTMl form is valid and not empty
  return mp[param]
