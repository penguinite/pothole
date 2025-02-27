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