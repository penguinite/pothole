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

# From libpothole or pothole's server codebase
import libpothole/[lib,conf,database]
import assets

# From stdlib
import std/tables
import std/strutils except isEmptyOrWhitespace

# From nimble/other sources
import mummy

let
  config = setup(getConfigFilename())
  staticFolder = initStatic(config)
  db = initFromConfig(config)



#! Actual prologue routes

# our serveStatic route reads from static/FILENAME and renders it as a template.
# This helps keep everything simpler, since we just add our route to the string, it's asset and
# Bingo! We've got a proper route that also does templating!

# But this won't work for /auth/ routes!

const staticURLs*: Table[string,string] = {
  "/": "index.html", 
  "/about": "about.html", "/about/more": "about.html", # About pages, they run off of the same template.
}.toTable

proc prepareTable(config: Table[string, string], db: DbConn): Table[string,string] =
  var table = { # Config table for the templating library.
    "name":config.getString("instance","name"), # Instance name
    "description":config.getString("instance","description"), # Instance description
    "version":"", # Pothole version
    "staff": "<p>None</p>", # Instance staff (Any user with the admin attribute)
    "rules": "<p>None</p>" # Instance rules (From config)
  }.toTable

   # Add admins and other staff
  if config.getBool("web","show_staff"):
    table["staff"] = "" # Clear whatever is in it first.
    # Build the list, item by item using database functions.
    table["staff"].add("<ul>")
    for user in db.getAdmins():
      table["staff"].add("<li><a href=\"/@" & user & "\">" & user & "</a></li>") # Add every admin as a list item.
    table["staff"].add("</ul>")

   # Add instance rules
  if config.exists("instance","rules"):
    table["rules"] = "" # Again, clear whatever is in it first.
    # Build the list, item by item using data from the config file.
    table["rules"].add("<ol>")
    for rule in config.getArray("instance","rules"):
      table["rules"].add("<li>" & rule & "</li>")
    table["rules"].add("</ol>")

  when not defined(phPrivate):
    if config.getBool("web","show_version"):
      table["version"] = lib.phVersion

  return table

#! Mummy relies on gcsafe indirectly.
## TODO: Figure out how to stop making it rely on that stupid pragma.

proc serveStatic*(req: Request) =
  var headers: HttpHeaders
  headers["Content-Type"] = "text/html"

  var path = req.uri

  if path.endsWith("/") and path != "/": path = path[0..^2]
  # If the path has a slash at the end, remove it.
  # Except if the path is the root, aka. literally just a slash

  {.gcsafe.}:
    req.respond(200, headers, renderTemplate(
      getAsset(staticFolder, staticURLs[path]),
      prepareTable(config, db)
    ))
  
proc serveCSS*(req: Request) = 
  var headers: HttpHeaders
  headers["Content-Type"] = "text/css"
  
  # If I change the "static/" to staticFolder then it won't work
  # because nim is a shit language that doesn't recognize let as immutable.
  {.gcsafe.}:
    req.respond(200, headers, getAsset(staticFolder, "style.css"))