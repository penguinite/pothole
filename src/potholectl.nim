# Copyright © Leo Gavilieau 2024-2025 <penguinite@tuta.io>
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
# potholectl:
## Potholectl is a command-line tool that provides a nice and simple interface to many of Pothole's internals.
## It can be used to create new users, delete posts, add new MRF policies, setup database containers and more!
## Generally, this command aims to be a Pothole instance administrator's best friend.
# From Pothole & Quark:
import quark/[db, strextra, auth_codes, sessions, oauth, apps, users, posts, shared, crypto]
import pothole/[database, lib, conf]

# Standard library
import std/[osproc, os, times]
import std/strutils except isEmptyOrWhitespace, parseBool

# Third-party libraries
import cligen, rng

# Disable MRF on non-POSIX builds.
when defined(posix):
  import std/[posix, dynlib, mrf]

proc exec*(cmd: string): string {.discardable.} =
  try:
    log "Executing: ", cmd
    let (output,exitCode) = execCmdEx(cmd)
    if exitCode != 0:
      log "Command returns code: ", exitCode
      log "command returns output: ", output
      return ""
    return output
  except CatchableError as err:
    log "Couldn't run command:", err.msg

proc user_new*(args: seq[string], admin = false, moderator = false, require_approval = false, display = "Default Name", bio = "", config = "pothole.conf"): int =
  ## This command creates a new user and adds it to the database.
  ## It uses the following format: NAME EMAIL PASSWORD
  ## 
  ## So to add a new user, john for example, you would run potholectl user new john johns@email.com johns_password
  ## 
  ## The users created by this command are approved by default.
  ## Although that can be changed with the require-approval CLI argument
  if len(args) != 3:
    error "Invalid number of arguments, expected 3."

  # Then we check if our essential args is empty.
  # If it is, then we error out
  var
    handle = args[0]
    email = args[1]
    password = args[2]
  if handle.isEmptyOrWhitespace() or password.isEmptyOrWhitespace() or email.isEmptyOrWhitespace():
    error "Required argument is either empty or non-existent."

  let
    cnf = setup(config)
    db = setup(
      cnf.getDbUser(),
      cnf.getDbName(),
      cnf.getDbHost(),
      cnf.getDbPass(),
    )
  
  var user = newUser(
    handle = handle,
    local = true,
    password = password
  )

  user.email = email
  user.name = display
  user.bio = escape(bio)
  user.is_approved = not require_approval
  user.admin = admin
  user.moderator = moderator
    
  try:
    db.addUser(user)
  except CatchableError as err:
    error "Failed to insert user: ", err.msg
  
  log "Successfully inserted user"
  echo "Login details:"
  echo "name: ", user.handle
  echo "password: ", password
  return 0

proc user_delete*(args: seq[string], purge = false, id = true, handle = false, config = "pothole.conf"): int =
  ## This command deletes a user from the database, you can either specify a handle or user id.
  if len(args) != 1:
    error "Invalid number of arguments"
  
  var
    thing = args[0]
    isId = id

  # If the user tells us its a handle
  # or if "thing" has an @ symbol
  # then its a handle.
  if not id:
    if handle or "@" in thing:
      isId = false
  
  # If the user supplies both -i and -n then error out and ask them which it is.
  if id and handle:
    error "This can't both be a name and id, which is it?"
  

  if thing.isEmptyOrWhitespace():
    error "Argument is empty"

  let
    cnf = setup(config)
    db = setup(
      cnf.getDbUser(),
      cnf.getDbName(),
      cnf.getDbHost(),
      cnf.getDbPass(),
    )
    
  if db.userIdExists(thing) and db.userHandleExists(thing) and "@" notin thing:
    error "Potholectl can't infer whether this is an ID or a handle, please re-run with the -i or -n flag depending on if this is an id or name"

  # Try to convert the thing we received into an ID.
  # So it's easier to handle
  var id = ""
  case isId:
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

  for pid in db.getPostsByUser(id):
    try:
      # If the user says its ok to put extra strain on the db
      # and actually delete the posts made by this user
      # Then we'll do it! Otherwise, we'll just reset the sender to "null"
      # (Which marks it as deleted internally but doesnt do anything.)
      if purge:
        echo "Deleting post \"", pid, "\""
        db.deletePost(pid)
      else:
        echo "Marking post \"", pid, "\" as deleted"
        db.updatePostSender(pid, "null")
    except CatchableError as err:
      error "Failed to process user posts: ", err.msg
    
  # Delete the user
  try:
    db.deleteUser(id)
  except CatchableError as err:
    error "Failed to delete user: ", err.msg
    
  echo "If you're seeing this then there's a high chance your command succeeded."

proc user_id*(args: seq[string], quiet = false, config = "pothole.conf"): int =
  ## This command is a shorthand for user info -i
  ## 
  ## It basically prints the user id of whoever's handle we just got
  if len(args) != 1:
    if quiet: quit(1)
    error "Invalid number of arguments"
  
  if args[0].isEmptyOrWhitespace():
    if quiet: quit(1)
    error "Empty or mostly empty argument"
  
  let
    cnf = setup(config)
    db = setup(
      cnf.getDbUser(),
      cnf.getDbName(),
      cnf.getDbHost(),
      cnf.getDbPass(),
    )

  if not db.userHandleExists(args[0]):
    if quiet: quit(1)
    error "You must provide a valid user handle to this command"
    
  echo db.getIdFromHandle(args[0])
  return 0

proc user_handle*(args: seq[string], quiet = false, config = "pothole.conf"): int =
  ## This command is a shorthand for user info -h
  ## 
  ## It basically prints the user handle of whoever's id we just got
  if len(args) != 1:
    if quiet: quit(1)
    error "Invalid number of arguments"
  
  if args[0].isEmptyOrWhitespace():
    if quiet: quit(1)
    error "Empty or mostly empty argument"
  
  let
    cnf = setup(config)
    db = setup(
      cnf.getDbUser(),
      cnf.getDbName(),
      cnf.getDbHost(),
      cnf.getDbPass(),
    )

  if not db.userIdExists(args[0]):
    if quiet: quit(1)
    error "You must provide a valid user id to this command"
    
  echo db.getHandleFromId(args[0])
  return 0

# I hate this just as much as you do but cligen complains without so here goes.
proc user_info*(args: seq[string], id = false, handle = false,
    display = false, moderator = false, admin = false, request = false, frozen = false,
    email = false, bio = false, password = false, salt = false, kind = false,
    quiet = false, config = "pothole.conf"): int = 

  ## This command retrieves information about users.
  ## By default it will display all information!
  ## You can also choose to see specific bits with the command flags
  if len(args) != 1:
    if quiet: quit(1)
    error "Invalid number of arguments"
  
  if args[0].isEmptyOrWhitespace():
    if quiet: quit(1)
    error "Empty or mostly empty argument"
  
  let
    cnf = setup(config)
    db = setup(
      cnf.getDbUser(),
      cnf.getDbName(),
      cnf.getDbHost(),
      cnf.getDbPass(),
    )

  var user: User
  if db.userHandleExists(args[0]):
    if not quiet:
      log "Using provided args as a user handle"
    user = db.getUserByHandle(args[0])
  elif db.userIdExists(args[0]):
    if not quiet:
      log "Using provided args as a user ID"
    user = db.getUserById(args[0])
  else:
    error "No valid user handle or id exists for the provided args..."


  var output = ""
  proc print(s,s2: string) =
    if quiet:
      output.add s2
    else:
      output.add s & ": " & s2

  if id: print "ID", user.id
  if handle: print "Handle", user.handle
  if display: print "Display name", user.name
  if admin: print "Admin status", $(user.admin)
  if moderator: print "Moderator status", $(user.admin)
  if request: print "Approval status:", $(user.is_approved)
  if frozen: print "Frozen status:", $(user.is_frozen)
  if email: print "Email", user.email
  if bio: print "Bio", user.bio
  if password: print "Password (hashed)", user.password
  if salt: print "Salt", user.salt
  if kind: print "User type": $(user.kind)

  if output == "":
    echo $user
  else:
    echo output
  return 0
{.warning[ImplicitDefaultValue]: on.}

proc user_hash*(args: seq[string], algo = "", quiet = false): int =
  ## This command hashes the given password with the latest KDF function.
  ## You can also customize what function it will use with the algo command flag.
  ## 
  ## Format: potholectl user hash [PASSWORD] [SALT]
  ## 
  ## [PASSWORD] is required, whilst [SALT] can be left out.
  if len(args) == 0 or len(args) > 2:
    error "Invalid number of arguments"
    
  var
    password = args[0]
    salt = ""
    kdf = crypto.latestKdf
  
  if algo != "":
    kdf = toKdfFromDb(algo)

  if len(args) == 2:
    salt = args[1]
    
  var hash = hash(
    password, salt, kdf
  )

  if quiet:
    echo hash
    return 0

  echo "Hash: \"", hash, "\""
  echo "Salt: \"", salt, "\""
  echo "KDF Id: ", kdf
  echo "KDF Algorithm: ", toHumanString(kdf)

# TODO: Missing commands:
#   user_mod: Changes a user's moderator status
#   user_admin: Changes a user's administrator status
#   user_password: Changes a user's password
#   user_freeze: Change's a user's frozen status
#   user_approve: Approves a user's registration
#   user_deny: Denies a user's registration

proc post_new*(data: seq[string], mentioned = "", replyto = "", date = "", config = "pothole.conf"): int =
  ## This command creates a new post and adds it to the database.
  ## 
  ## Usage: potholectl post new [SENDER] [CONTENT].
  ## Where [SENDER] is a handle and [CONTENT] is anything you would like.
  ## 
  ## Here is an example: potholectl post new john "Hello World!"
  ## 
  ## This command requires that the user's you'll be sending from are real and exist in the database.
  ## Otherwise, you'll be in database hell.
  if len(data) != 2:
    error "Missing number of arguments"
  
  var
    sender, content = ""
    recipients: seq[string]
    written: DateTime = utc(now())
  
  if date != "":
    written = toDateFromDb(date)

  # Fill up every bit of info we need
  # First the plain command-line mandatory arguments
  sender = data[0]
  content = data[1]
  
  # Then we check if our essential data is empty.
  # If it is, then we error out and tell the user to RTFM (but kindly)
  if sender.isEmptyOrWhitespace() or content.isEmptyOrWhitespace():
    error "Sender or content is mostly empty."

  if '@' in sender:
    error "We can't create posts for remote users."

  let
    cnf = config.setup()
    db = setup(
      cnf.getDbName(),
      cnf.getDbUser(),
      cnf.getDbHost(),
      cnf.getDbPass(),
      true
    )

  # Double check that every recipient is real and exists.
  for user in mentioned.smartSplit(','):
    if db.userHandleExists(user):
      recipients.add(db.getIdFromHandle(user))
      continue
    if db.userIdExists(user):
      recipients.add(user)
  
  var post = newPost(
    sender = sender,
    content = @[text(content, written)],
    replyto = replyto,
    recipients = recipients,
    written = written
  )

  # Some extra checks
  # replyto must be an existing post.
  # sender must be an existing user.
  if not db.userIdExists(sender):
    log "Assuming sender is a handle and not an id..."
    if not db.userHandleExists(sender):
      error "Sender doesn't exist in the database at all"
    log "Converting sender's handle into an ID."
    post.sender = db.getIdFromHandle(sender)
  
  if not db.postIdExists(replyto) and not replyto.isEmptyOrWhitespace():
    error "Replyto must be the ID of a pre-existing post."

  try:
    db.addPost(post)
    log "Successfully inserted post"
  except CatchableError as err:
    error "Failed to insert post: ", err.msg

proc post_get*(args: seq[string], limit = 10, id = true, handle = false, config = "pothole.conf"): int =
  ## This command displays a user's most recent posts, it only supports displaying text-based posts as of now.
  ## 
  ## You can adjust how many posts will be shown with the `limit` parameter
  if len(args) != 1:
    error "Invalid number of arguments"
  
  var
    thing = args[0]
    isId = id

  # If the user tells us its a handle
  # or if "thing" has an @ symbol
  # then its a handle.
  if not id:
    if handle or "@" in thing:
      isId = false
  
  # If the user supplies both -i and -n then error out and ask them which it is.
  if id and handle:
    error "This can't both be a name and id, which is it?"
  

  if thing.isEmptyOrWhitespace():
    error "Argument is empty"

  let
    cnf = setup(config)
    db = setup(
      cnf.getDbUser(),
      cnf.getDbName(),
      cnf.getDbHost(),
      cnf.getDbPass(),
    )
    
  if db.userIdExists(thing) and db.userHandleExists(thing) and "@" notin thing:
    error "Potholectl can't infer whether this is an ID or a handle, please re-run with the -i or -n flag depending on if this is an id or name"

  # Try to convert the thing we received into an ID.
  # So it's easier to handle
  var id = ""
  case isId:
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

# TODO: Missing commands:
#   post_del: Deletes a post
#   post_purge: Deletes old posts made by the null (deleted) user.

when not defined(posix):
  proc mrf_view*(filenames: seq[string]): int =
    ## This command only works on Linux/POSIX systems, MRF is disabled for Windows builds.
    return 0
else:
  proc mrf_view*(filenames: seq[string]): int =
    ## Shows a helpful feature summary for a custom MRF policy.
    ## 
    ## When given a filename, or multiple filenames, it will go through and find the module.
    ## Then it will link it and run a bunch of tests to see what filters it has.
    ## 
    ## If there is no output from this command, then you either gave it a module it couldn't load
    ## or the MRF policy you successfully loaded has no filters.
    ## 
    ## Obviously, don't run this command on anything you didn't compile yourself
    ## Since it's an unsafe command.
    if len(filenames) == 0:
      echo "Please provide modules to inspect."
      quit(1)

    for filename in filenames:
      if isEmptyOrWhitespace(filename):
        continue

      if not fileExists(filename):
        echo "File " & filename & " does not exist."
        continue
      
      echo "Inspecting file " & filename
      var lib: LibHandle
      if not filename.startsWith('/') or not filename.startsWith("./"):
        lib = loadLib("./" & filename)
      else:
        lib = loadLib(filename)

      if lib == nil:
        echo "Failed to load library, dlerror output: ", $dlerror()

      if lib.getFilterIncomingPost() != nil:
        echo "This MRF policy filters incoming posts"
      if lib.getFilterOutgoingPost() != nil:
        echo "This MRF policy filters outgoing posts"

      if lib.getFilterIncomingUser() != nil:
        echo "This MRF policy filters incoming users"
      if lib.getFilterOutgoingUser() != nil:
        echo "This MRF policy filters outgoing users"

      #[
      if lib.getFilterIncomingActivity() != nil:
        echo "This MRF policy filters incoming activities"
      if lib.getFilterOutgoingActivity() != nil:
        echo "This MRF policy filters outgoing activities"
      ]#
    return 0

when not defined(posix):
  proc mrf_compile*(filenames: seq[string]): int =
    ## This command only works on Linux/POSIX systems, MRF is disabled for Windows builds.
    return 0
else:
  proc mrf_compile*(filenames: seq[string]): int =
    ## Compiles an MRF policy from Nim to a dynamic module
    ## 
    ## When given a filename, or multiple filenames, it will go through and compile each module.
    ## 
    ## Obviously, don't run this command on anything you didn't read the source of
    ## Since compile-time code *can* be dangerous to run
    if len(filenames) == 0:
      echo "Please provide files to compile."
      quit(1)

    for filename in filenames:
      if isEmptyOrWhitespace(filename):
        continue

      if not fileExists(filename):
        echo "File " & filename & " does not exist."
        continue

      let cmd = "nim cpp --app:lib " & filename
      echo "Executing command: " & cmd
      discard execShellCmd(cmd)

    return 0

proc db_check*(config = "pothole.conf"): int =
  ## This command initializes a database with schema checking enabled,
  ## you can use it to test if the database needs migration.
  let cnf = conf.setup(config)
  log "Re-running database initialization with schema checking enabled."
  discard setup(
    cnf.getDbName(),
    cnf.getDbUser(),
    cnf.getDbHost(),
    cnf.getDbPass(),
    true
  )
  return 0

proc db_purge*(config = "pothole.conf"): int =
  ## This command purges the entire database, it removes all tables and all the data within them.
  ## It's quite obvious but this command will erase any data you have, so be careful.
  let cnf = conf.setup(config)
  log "Cleaning everything in database"
  init(
    cnf.getDbName(),
    cnf.getDbUser(),
    cnf.getDbHost(),
    cnf.getDbPass(),
  ).cleanDb()
  return 0

proc db_docker*(config = "pothole.conf", name = "potholeDb", allow_weak_password = false, expose_externally = false, ipv6 = false): int =
  ## This command creates a postgres docker container that automatically works with pothole.
  ## It reads the configuration file and takes note of the database configuration.
  ## And then it pulls the alpine:postgres docker image, and starts it up with the correct port, name, password anything.
  ## 
  ## If this command detects that you are using the default password ("SOMETHING_SECRET") then it will change it to an autogenerated 64 char length password for security's sake.
  ## In most cases, this behavior is perfectly acceptable and fine. But you can disable it with the -a or --allow-weak-password option.
  let cnf = conf.setup(config)
  log "Setting up postgres docker container according to config file"
  var
    # Sick one liner to figure out the port we need to expose.
    port = split(getDbHost(cnf), ":")[high(split(getDbHost(cnf), ":"))]
    password = cnf.getDbPass()
    dbname = cnf.getDbName()
    user = cnf.getDbUser()
    host = ""

  if port.isEmptyOrWhitespace():
    port = "5432"
    
  if not expose_externally:
    if ipv6: host.add("::1:")
    else: host.add("127.0.0.1:")
  host.add(port & ":5432")
    
  if password == "SOMETHING_SECRET" and not allow_weak_password:
    log "Changing weak database password to something more secure"
    password = randstr(64)
    echo "Please update the config file to reflect the following changes:"
    echo "[db] password is now \"", password, "\""
  
  log "Pulling docker container"
  discard exec "docker pull postgres:alpine"
  log "Creating the container itself"
  let id = exec "docker run --name $# -d -p $# -e POSTGRES_USER=$# -e POSTGRES_PASSWORD=$# -e POSTGRES_DB=$# postgres:alpine" % [name, host, user, password, dbname]
  if id == "":
    error "Please investigate the above errors before trying again."
  return 0

proc db_psql*(config = "pothole.conf"): int = 
  ## This command opens a psql shell in the database container.
  ## This is useful for debugging operations and generally figuring out where we went wrong. (in life)
  ## 
  ## Note: This command only works with the database container created by the db_docker cmd.
  let
    cnf = conf.setup(config)
    cmd = "docker exec -it potholeDb psql -U " & cnf.getDbUser() & " " & cnf.getDbName()
  echo "Executing: ", cmd
  discard execShellCmd cmd

proc db_run*(file: string, config = "pothole.conf"): int =
  ## Run any SQL-containing file on your Pothole database!
  ## 
  ## Note: Due to technical limitations, the file **HAS** to have each query/command on a single line!
  ## Seriously, if you forget this, you're gonna have an awful time! I am not joking!!!
  ## 
  ## Also, PLEASE BE SANE! DON'T RUN ANYTHING THAT YOU DIDN'T DOUBLE CHECK!
  let cnf = conf.setup(config)
  let db = init(
    cnf.getDbName(),
    cnf.getDbUser(),
    cnf.getDbHost(),
    cnf.getDbPass(),
  )

  for line in readFile(file).splitLines:
    echo "Running: ", line
    db.exec(sql(line))


proc db_clean*(config = "pothole.conf"): int =
  ## This command runs some cleanup procedures.
  let cnf = conf.setup(config)
  let db = init(
    cnf.getDbName(),
    cnf.getDbUser(),
    cnf.getDbHost(),
    cnf.getDbPass(),
  )
  log "Cleaning up sessions"
  for session in db.cleanSessionsVerbose():
    log "Cleaned up session belonging to \"", db.getHandleFromId(session[1]), "\""
  log "Cleaning up authentication codes"
  for code in db.cleanupCodesVerbose():
    log "Cleaned up auth code belonging to \"", db.getHandleFromId(code[1]), "\""
  log "Purging old apps/clients"
  db.purgeOldApps()
  log "Purging old oauth tokens"
  db.purgeOldOauthTokens()

proc ids*(): int =
  ## Educational material about IDs
  echo  """
Pothole abstract nearly every single thing into some object with an "id"
Users have IDs and posts have IDs.
So do activities, media attachments, reactions, boosts and so on.

Internally, pothole translates any human-readable data (such as a handle, see `potholectl handles`)
into an id that it can use for manipulation, data retrieval and so on.

This slightly complicates everything but potholectl will try to make an educated guess.
If you do know whether something is an ID or not, then you can use the -i flag to tell potholectl not to double check.
Of course, this differs with every command but it should be possible."""
  return 0

proc handles*(): int =
  ## Educational material about handles
  echo """
A handle is basically what pothole calls the "username"
A handle can be as simple as "john" or "john@example.com"
A handle is not the same thing as an email address.
In pothole, the handle is used as a login name and also as a user finding mechanism (for federation)"""
  return 0

proc dates*(): int =
  ## Educational material about date handling in Pothole.
  echo """
This is not exactly a subsystem but a help entry for people confused by dates in potholectl.
Dates in potholectl are formatted like so: yyyy-MM-dd HH:mm:ss
This means the following:
  1. 4 numbers for the year, and then a hyphen/dash (-)
  2. 2 numbers for the month, and then a hyphen/dash (-)
  3. 2 numbers for the day, and then a hyphen/dash (-)
  4. A space
  5. 2 numbers for the hour and then a colon (:)
  6. 2 numbers for the minute and then a colon (:)
  7. 2 numbers for the second

Here are examples of dates in this format:
UNIX Epoch starting date: "1970-01-01 00:00:00"
Year 2000 problem date: "1999-12-31 23:59:59"
Year 2038 problem date: "2038-01-19 03:14:07"
Year 2106 problem date: "2106-02-07 06:28:15"
The date this was written: "2024-03-23 13:09:26"

Make sure to wrap the date around with double quotes, that way there won't be any mistakes!"""
  return 0

dispatchMulti(
  [post_new,
    help = {
      "mentioned": "A comma-separated list of users that are mentioned in this post.",
      "replyto": "The specific post we are replying to by its ID.",
      "date": "The specific date of when the post was written. See \"potholectl dates\"",
      "config": "Location to config file"
    }],

  [user_new,
    help = {
    "admin": "Makes the user an administrator",
    "moderator": "Makes the user a moderator",
    "require-approval": "Turns user into an unapproved user",
    "display": "Specifies the display name for the user",
    "bio": "Specifies the bio for the user",
    "config": "Location to config file"
    }],

  [user_delete,
    help = {
      "id": "Specifies whether or not the thing provided is an ID",
      "handle": "Specifies whether or not the thing provided is an handle",
      "purge": "Whether or not to delete all the user's posts and other data",
      "config": "Location to config file"
    }],

  [user_info,
    help = {
      "quiet": "Makes the program a whole lot less noisy.",
      "id":"Print only user's ID",
      "handle":"Print only user's handle",
      "display":"Print only user's display name",
      "admin": "Print user's admin status",
      "moderator": "Print user's moderator status",
      "request": "Print user's approval request",
      "frozen": "Print user's frozen status",
      "email": "Print user's email",
      "bio":"Print user's biography",
      "password": "Print user's password (hashed)",
      "salt": "Print user's salt",
      "kind": "Print the user's type/kind",
      "config": "Location to config file"
    }],

  [user_id,
    help = {
      "quiet": "Print only the ID and nothing else.",
      "config": "Location to config file"
    }],

  [user_handle,
    help = {
      "quiet": "Print only the handle and nothing else.",
      "config": "Location to config file"
    }],

  [user_hash,
    help = {
      "quiet": "Print only the hash and nothing else.",
      "algo": "Allows you to specify the KDF algorithm to use."
    }],

  [db_check, help = {"config": "Location to config file"}],
  [db_clean, help = {"config": "Location to config file"}],
  [db_purge, help = {"config": "Location to config file"}],
  [db_psql, help = {"config": "Location to config file"}],
  [db_run, help = {"file": "Location to SQL script.", "config": "Location to config file"}],
  [db_docker,
    help= {
      "config": "Location to config file",
      "name": "Sets the name of the database container",
      "allow_weak_password": "Does not change password automatically if its weak",
      "expose_externally": "Exposes the database container (potentially to the outside world)",
      "ipv6": "Sets some IPv6-specific options in the container"
    }],

  [mrf_view, help={"filenames": "List of modules to inspect"}],
  [mrf_compile, help={"filenames": "List of files to compile"}],

  [ids], [handles], [dates]
)
