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
#
# ctl/user.nim:
## User-related operations for potholectl
## This simply parses the subsystem & command (and maybe arguments)
## and it calls the appropriate function from potholepkg/database.nim and potholepkg/user.nim

# From somewhere in Potholectl
import shared

# From somewhere in Quark
import quark/[database, user, strextra]

# From somewhere in Pothole
import pothole/[database,lib,conf]

# From standard libraries
from std/tables import Table
import std/strutils except isEmptyOrWhitespace, parseBool

proc processCmd*(cmd: string, data: seq[string], args: Table[string,string]) =
  if args.check("h","help"):
    helpPrompt("user",cmd)

  var config: ConfigTable
  if args.check("c", "config"):
    config = conf.setup(args.get("c","config"))
  else:
    config = conf.setup(getConfigFilename())

  let db = setup(
    config.getDbUser(),
    config.getDbName(),
    config.getDbHost(),
    config.getDbPass(),
    true
  )

  case cmd:
  of "new":
    var
      name = ""
      email = ""
      password = ""
      display = name
      bio = ""

    # Fill up every bit of info we need
    # First the plain command-line mandatory arguments
    if len(data) > 0:
      name = data[0]
      password = data[1]
    
    # And then the short and long command-line options
    if args.check("n","name"):
      name = args.get("n","name")
    
    if args.check("e","email"):
      email = args.get("e","email")

    if args.check("d", "display"):
      display = args.get("d", "display")
    else:
      display = sanitizeHandle(name)
    
    if args.check("p", "password"):
      password = args.get("p", "password")
    
    if args.check("b", "bio"):
      bio = args.get("b", "bio")
    
    # Then we check if our essential data is empty.
    # If it is, then we error out and tell the user to RTFM (but kindly)
    if name.isEmptyOrWhitespace() or password.isEmptyOrWhitespace():
      if args.check("q","quiet"): quit(1)
      log "Invalid command usage"
      log "You can always freshen up your knowledge on the CLI by re-running the same command with -h or --help"
      log "In fact, for your convenience! That's what we will be doing! :D"
      helpPrompt("user", cmd)

    var user = newUser(
      handle = name,
      local = true,
      password = password,
    )

    user.email = email
    user.name = display
    user.bio = escape(bio)
    user.is_approved = true

    if args.check("a","admin"): user.admin = true
    if args.check("m","moderator"): user.moderator = true
    if args.check("r","require-approval"): user.is_approved = false
    
    try:
      db.addUser(user)
      if not args.check("q","quiet"):
        log "Successfully inserted user"
        echo "Login details:"
      echo "name: ", user.handle
      echo "password: ", password
    except CatchableError as err:
      if not args.check("q","quiet"):
        error "Failed to insert user: ", err.msg
      quit(1)
  of "delete", "del", "purge":
    var
      thing = ""
      idOrhandle = false # True means it's an id, False means it's a handle.
    if len(data) > 0:
      thing = data[0]
    
    if db.userIdExists(thing) and db.userHandleExists(thing) and "@" notin thing:
      error "Potholectl can't infer whether this is an ID or a handle, please re-run with either -i or -n"
    
    # If there's an @ symbol then it's highly likely it's a handle
    if args.check("i", "id"):
      idOrhandle = true
    
    if args.check("n", "name") or "@" in thing:
      idOrhandle = false

    # Try to convert the thing we received into an ID.
    # So it's easier    
    var id = ""
    case idOrhandle:
    of false:
      # It's a handle
      if not db.userHandleExists(thing):
        error "User handle doesn't exist"
      id = db.getIdFromHandle(thing)
    of true:
      # It's an id
      if not db.userIdExists(thing):
        error "User id doesn't exist"
      id = thing
    
    # The `null` user is important.
    # We simply cannot delete it otherwise we will be in database hell.
    if id == "null":
      error "Deleting the null user is not allowed."

    if args.check("p", "purge") or cmd == "purge":
      # Delete every post first.
      try:
        db.deletePosts(db.getPostIDsByUserWithID(id))
      except CatchableError as err:
        error "Failed to delete posts by user: ", err.msg
    else:
      # We must reassign every post made this user to the `null` user
      # Otherwise the database will freakout.
      try:
        db.reassignSenderPosts(db.getPostIDsByUserWithID(id), "null")
      except CatchableError as err:
        log "There's probably some database error somewhere..."
        error "Failed to reassign posts by user: ", err.msg
    
    # Delete the user
    try:
      db.deleteUser(id)
    except CatchableError as err:
      error "Failed to delete user: ", err.msg
    
    echo "If you're seeing this then there's a high chance your command succeeded."
  of "id":
    if len(data) == 0:
      if args.check("q","quiet"): quit(1)
      log "You must provide an argument to this command"
      helpPrompt("user","id")

    if not db.userHandleExists(data[0]):
      if args.check("q","quiet"): quit(1)
      log "You must provide a valid user handle to this command"
      helpPrompt("user","id")
    
    echo db.getIdFromHandle(data[0])
  of "handle":
    if len(data) == 0:
      if args.check("q","quiet"): quit(1)
      log "You must provide an argument to this command"
      helpPrompt("user","handle")
    
    if not db.userIdExists(data[0]):
      if args.check("q","quiet"): quit(1)
      log "You must provide a valid user ID to this command"
      helpPrompt("user","handle")
    
    echo db.getHandleFromId(data[0])
  of "info":
    if len(data) == 0:
      if args.check("q","quiet"): quit(1)
      log "You must provide an argument to this command"
      helpPrompt("user", "info")
    
    var user: User
    if db.userHandleExists(data[0]):
      if not args.check("q","quiet"):
        log "Using provided data as a user handle"
      user = db.getUserByHandle(data[0])
    elif db.userIdExists(data[0]):
      if not args.check("q","quiet"):
        log "Using provided data as a user ID"
      user = db.getUserById(data[0])
    else:
      error "No valid user handle or id exists for the provided data..."
    
    proc printSpecificInfo(short, long, name, data: string) = 
      if args.check(short, long):
        if args.check("q","quiet"):
          echo data
        else:
          echo name, ": \"", data , "\""
    
    if len(args) > 0:
      printSpecificInfo("i","id", "ID", user.id)
      printSpecificInfo("h","handle", "Handle", user.handle)
      printSpecificInfo("d","display", "Display name", user.name)
      printSpecificInfo("a","admin", "Admin status", $user.admin)
      printSpecificInfo("m","moderator", "Moderator status", $user.moderator)
      printSpecificInfo("r","request", "Approval request status:", $user.is_approved)
      printSpecificInfo("f","frozen", "Frozen status:", $user.is_frozen)
      printSpecificInfo("e","email", "Email", user.email)
      printSpecificInfo("b","bio", "Bio", user.bio)
      printSpecificInfo("p","password", "Password (hashed)", user.password)
      printSpecificInfo("s","salt", "Salt", user.salt)
      printSpecificInfo("t","type", "Type", $user.kind)
    else:
      echo $user
  else:
    helpPrompt("user")