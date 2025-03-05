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
# user.nim:
## This module contains various functions and procedures for handling User objects.
## The User object type has been moved here after commit 9f3077d
## Database-related procedures are in db.nim

# From Quark
import quark/[shared, strextra, crypto]
import quark/private/[database, macros]
export User

# From the standard library
import std/strutils except isEmptyOrWhitespace, parseBool
import std/tables

# From elsewhere
import rng

# Whitelist set of characters.
# this filters anything that doesn't make a valid email.
const safeHandleChars*: set[char] = {
  'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k',
  'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v',
  'w', 'x', 'y', 'z', '1', '2', '3', '4', '5', '6', '7',
  '8', '9', '0', '.', '@', '-',
}

func sanitizeHandle*(handle: string, charset: set[char] = safeHandleChars): string =
  ## Checks a string against user.unsafeHandleChars
  ## This is mostly used for checking for valid emails and handles.
  if handle.isEmptyOrWhitespace():
    return "" 

  for ch in toLowerAscii(handle):
    if ch in charset:
      result.add(ch)

  return result

proc newUser*(handle: string, local: bool = false, password: string = ""): User =
  ## This procedure just creates a user and that's it
  ## We will fill out some basic details, like if you supply a password, name
  
  # First off let's do the things that are least likely to create an error in any way possible.
  result.id = randstr()
  
  result.salt = ""
  if local:
    result.salt = randstr(12)
    result.domain = ""
  
  result.kdf = latestKdf # Always assume user is using latest KDF because why not?
  result.local = local
  result.admin = false # This is false by default.
  result.moderator = false # This is false by default.
  result.is_frozen = false # Always assume user isn't frozen.
  result.is_approved = true # Always assume user is approved.
  result.is_verified = false # Always assume user isn't verified.
  result.discoverable = true # This is the default.
  result.kind = Person # Even if its a group, service or application then it doesn't matter.

  # Sanitize handle before using it
  let newhandle = sanitizeHandle(handle)
  if newhandle.isEmptyOrWhitespace():
    return User() # We can't use the error template for some reason.
  result.handle = newhandle

  # Use handle as name
  result.name = newhandle
  
  result.password = ""
  if local and password != "":
    result.password = hash(password, result.salt)  

  # The only things remaining are email and bio which the program can guess based on its own context clues (Such as if the user is local)
  return result

proc newUserX*(
  handle: string, local: bool, password = "", domain = "", name = "", email = "", bio = "", id = randstr(), salt = "",
  kdf = latestKdf, admin = false, moderator = false, frozen = false, approved = true, verified = false, discoverable = true, kind = UserType.Person
): User =
  result.id = id
  result.kind = kind
  result.handle = sanitizeHandle(handle)
  result.domain = domain
  result.name = name
  result.local = local
  result.email = email
  result.bio = bio
  result.kdf = kdf
  result.admin = admin
  result.moderator = moderator
  result.discoverable = discoverable
  result.is_frozen = frozen
  result.is_verified = verified
  result.is_approved = approved
  result.salt = salt
  
  if local and salt == "":
    result.salt = randstr(12)
  
  if local and password != "":
    result.password = hash(password,salt,kdf)
  else:
    result.password = password 
  return result

proc addUser*(db: DbConn, user: User) = 
  ## Add a user to the database
  ## This procedure expects an escaped user to be handed to it.
  var testStmt = sql"SELECT local FROM users WHERE ? = ?;"

  if has(db.getRow(testStmt, "handle", user.handle)): 
    raise newException(DbError, "User with same handle as \"" & user.handle & "\" already exists")

  if has(db.getRow(testStmt, "id", user.id)):
    raise newException(DbError, "User with same id as \"" & user.id & "\" already exists")
  
  db.autoStmt(User, "users", user)

proc getAdmins*(db: DbConn): seq[string] = 
  ## A procedure that returns the usernames of all administrators.
  for row in db.getAllRows(sql"SELECT handle FROM users WHERE admin = true;"):
    result.add(row[0])
  return result
  
proc getTotalLocalUsers*(db: DbConn): int =
  ## A procedure to get the total number of local users.
  result = 0
  for x in db.getAllRows(sql"SELECT is_approved FROM users WHERE local = true;"):
    inc(result)
  return result

proc getDomains*(db: DbConn): CountTable[string] =
  ## A procedure to get the all of the domains known by this server.
  for handle in db.getAllRows(sql"SELECT domain FROM users WHERE domain != '';"):
    result.inc(handle[0]) # Skip the username and add the domain.

proc getTotalDomains*(db: DbConn): int =
  result = 0
  for val in db.getDomains().values:
    result = result + val
  return result

proc userIdExists*(db: DbConn, id:string): bool =
  ## A procedure to check if a user exists by id
  ## This procedures does escape IDs by default.
  return has(db.getRow(sql"SELECT local FROM users WHERE id = ?;", id))

proc userHandleExists*(db: DbConn, handle:string): bool =
  ## A procedure to check if a user exists by handle
  ## This procedure does sanitize and escape handles by default
  return has(db.getRow(sql"SELECT local FROM users WHERE handle = ?;", sanitizeHandle(handle)))

proc userEmailExists*(db: DbConn, email: string): bool =
  ## Checks if a user with a specific email exists.
  return has(db.getRow(sql"SELECT local FROM users WHERE email = ?;", email))

proc getUserIdByEmail*(db: DbConn, email: string): string =
  ## Retrieves the user id by using the email associated with the user
  return db.getRow(sql"SELECT id FROM users WHERE email = ?;", email)[0]

proc getUserSalt*(db: DbConn, user_id: string): string = 
  if not db.userIdExists(user_id):
    raise newException(DbError, "User with id \"" & user_id & "\" doesn't exist.")

  return db.getRow(sql"SELECT salt FROM users WHERE id = ?;", user_id)[0]

proc getUserPass*(db: DbConn, user_id: string): string = 
  if not db.userIdExists(user_id):
    raise newException(DbError, "User with id \"" & user_id & "\" doesn't exist.")

  return db.getRow(sql"SELECT password FROM users WHERE id = ?;", user_id)[0]

proc isAdmin*(db: DbConn, user_id: string): bool =
  if not db.userIdExists(user_id):
    raise newException(DbError, "User with id \"" & user_id & "\" doesn't exist.")
  return db.getRow(sql"SELECT admin FROM users WHERE id = ?;", user_id) == @["t"]
  
proc isModerator*(db: DbConn, user_id: string): bool =
  if not db.userIdExists(user_id):
    raise newException(DbError, "User with id \"" & user_id & "\" doesn't exist.")
  return db.getRow(sql"SELECT moderator FROM users WHERE id = ?;", user_id) == @["t"]
  
proc getUserKDF*(db: DbConn, user_id: string): KDF =
  if not db.userIdExists(user_id):
    raise newException(DbError, "User with id \"" & user_id & "\" doesn't exist.")
  
  return toKdfFromDb(db.getRow(sql"SELECT kdf FROM users WHERE id = ?;", user_id)[0])

proc constructUserFromRow*(row: Row): User =
  ## A procedure that takes a database Row (From the users table)
  ## And turns it into a User object, ready for processing.
  ## It unescapes users by default
  result = User()

  # This looks ugly, I know, I had to wrap it with
  # two specific functions but we don't have to re-write this
  # even if we add new things to the User object. EXCEPT!
  # if we introduce new data types to the User object
  var i: int = -1;

  for key,value in result.fieldPairs:
    inc(i)
    # If its string, add it surrounding quotes
    # Otherwise add it whole
    when result.get(key) is bool:
      result.get(key) = parseBool(row[i])
    when result.get(key) is string:
      result.get(key) = row[i]
    when result.get(key) is int:
      result.get(key) = parseInt(row[i])
    when result.get(key) is UserType:
      result.get(key) = toUserType(row[i])
    when result.get(key) is KDF:
      result.get(key) = toKdfFromDb(row[i])

  return result

proc userFrozen*(db: DbConn, id: string): bool =
  ## Returns whether or not a user is frozen. ID must be a user id.
  if not db.userIdExists(id):
    raise newException(DbError, "Couldn't find user with id \"" & id & "\"")

  return db.getRow(sql"SELECT is_frozen FROM users WHERE id = ?;", id)[0] == "t"

proc userVerified*(db: DbConn, id: string): bool =
  ## Returns whether or not a user has a verifd email address. ID must be a user id.
  if not db.userIdExists(id):
    raise newException(DbError, "Couldn't find user with id \"" & id & "\"")

  return db.getRow(sql"SELECT is_verified FROM users WHERE id = ?;", id)[0] == "t"

proc userApproved*(db: DbConn, id: string): bool =
  ## Returns whether or not a user is approved. ID must be a user id.
  if not db.userIdExists(id):
    raise newException(DbError, "Couldn't find user with id \"" & id & "\"")

  return db.getRow(sql"SELECT is_approved FROM users WHERE id = ?;", id)[0] == "t"

proc getFirstAdmin*(db: DbConn): string =
  return db.getRow(sql"SELECT id FROM users WHERE admin = true;")[0]

proc adminAccountExists*(db: DbConn): bool = 
  return has(db.getRow(sql"SELECT id FROM users WHERE admin = true;"))

proc getUserBio*(db: DbConn, id: string): string = 
  return db.getRow(sql"SELECT bio FROM users WHERE id = ?;", id)[0]

proc getUserById*(db: DbConn, id: string): User =
  ## Retrieve a user from the database using their id
  ## This procedure returns a fully unescaped user, you do not need to do anything to it.
  ## This procedure expects a regular ID, it will sanitize and escape it by default.
  if not db.userIdExists(id):
    raise newException(DbError, "Couldn't find user with id \"" & id & "\"")

  return constructUserFromRow(db.getRow(sql"SELECT * FROM users WHERE id = ?;", id))

proc getUserByHandle*(db: DbConn, handle: string): User =
  ## Retrieve a user from the database using their handle
  ## This procedure returns a fully unescaped user, you do not need to do anything to it.
  ## This procedure expects a regular handle, it will sanitize and escape it by default.
  if not db.userHandleExists(handle):
    raise newException(DbError, "Couldn't find user with handle \"" & handle &  "\"")
    
  return constructUserFromRow(db.getRow(sql"SELECT * FROM users WHERE handle = ?;", sanitizeHandle(handle)))

proc updateUserByHandle*(db: DbConn, handle: string, column, value: string) =
  ## A procedure to update any user (The user is identified by their handle)
  ## The *only* parameter that is sanitized is the handle, the value has to be sanitized by your user program!
  ## Or else you will be liable to truly awful security attacks!
  ## For guidance, look at the sanitizeHandle() procedure in user.nim or the escape() procedure in the strutils module
  
  # Check if the user exists
  if not db.userHandleExists(handle):
    raise newException(DbError, "User with handle \"" & handle & "\" doesn't exist.")
  
  # Then update!
  db.exec(sql("UPDATE users SET " & column & " = ? WHERE handle = ?;"), value, sanitizeHandle(handle))
  
proc updateUserById*(db: DbConn, id, column, value: string) = 
  ## A procedure to update any user (The user is identified by their ID)
  
  # Check if the user exists
  if not db.userIdExists(id):
    raise newException(DbError, "User with id \"" & id & "\" doesn't exist.")

  # Then update!
  db.exec(sql("UPDATE users SET " & column & " = ? WHERE id = ?;"), value, id)

proc getIdFromHandle*(db: DbConn, handle: string): string =
  ## A function to convert a user handle to an id.
  ## This procedure expects a regular handle, it will sanitize and escape it by default.
  if not db.userHandleExists(handle):
    raise newException(DbError, "Couldn't find user with handle \"" & handle &  "\"")
  
  return db.getRow(sql"SELECT id FROM users WHERE handle = ?;", sanitizeHandle(handle))[0]

proc getHandleFromId*(db: DbConn, id: string): string =
  ## A function to convert a  id to a handle.
  ## This procedure expects a regular ID, it will sanitize and escape it by default.
  if not db.userIdExists(id):
    raise newException(DbError, "Couldn't find user with id \"" & id &  "\"")
  
  return db.getRow(sql"SELECT handle FROM users WHERE id = ?;", id)[0]

proc deleteUser*(db: DbConn, id: string) = 
  if not db.userIdExists(id):
    raise newException(DbError, "Couldn't find user with id \"" & id &  "\"")
  
  db.exec(sql"DELETE FROM users WHERE id = ?;", id)

proc deleteUsers*(db: DbConn, ids: varargs[string]) = 
  for id in ids:
    db.deleteUser(id)
