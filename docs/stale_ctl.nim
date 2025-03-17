# Disable MRF on non-POSIX builds.
when defined(posix):
  import std/[posix, dynlib], pothole/mrf

## A helper module for when you need to create custom MRF policies.
when defined(posix):
  import std/[tables, dynlib]
  import lib, conf
  import quark/[users, posts]
  export lib, conf, users, posts, tables

  type
    PostFilterProc* = proc (post: Post, config: ConfigTable): Post {.cdecl, nimcall.}
    UserFilterProc* = proc (user: User, config: ConfigTable): User {.cdecl, nimcall.}
    #ActivityFilterProc* = proc (user: Activity, config: ConfigTable): Activity {.cdecl, nimcall.}

  proc getFilterIncomingPost*(lib: LibHandle): PostFilterProc =
    return cast[PostFilterProc](lib.symAddr("filterIncomingPost"))

  proc getFilterOutgoingPost*(lib: LibHandle): PostFilterProc =
    return cast[PostFilterProc](lib.symAddr("filterOutgoingPost"))

  proc getFilterIncomingUser*(lib: LibHandle): UserFilterProc =
    return cast[UserFilterProc](lib.symAddr("filterIncomingUser"))

  proc getFilterOutgoingUser*(lib: LibHandle): UserFilterProc =
    return cast[UserFilterProc](lib.symAddr("filterOutgoingUser"))

  #[
  proc getFilterIncomingActivity*(lib: LibHandle): ActivityFilterProc =
    return cast[ActivityFilterProc](lib.symAddr("filterIncomingActivity"))

  proc getFilterOutgoingActivity*(lib: LibHandle): ActivityFilterProc =
    return cast[ActivityFilterProc](lib.symAddr("filterOutgoingActivity"))
  ]#
else:
  {.warning: "You're building Pothole on a non-POSIX system, therefore, MRF will be disabled.".}

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