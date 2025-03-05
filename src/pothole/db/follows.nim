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
#
# quark/db/follows.nim:
## This module contains all database logic for handling followers, following and so on.

import quark/private/database
import quark/[users, tag, strextra]
import std/sequtils

proc getFollowersQuick*(db: DbConn, user: string): seq[string] =
  ## Returns a set of handles that follow a specific user
  for row in db.getAllRows(sql"SELECT follower FROM follows WHERE following = ? AND approved = true;", user):
    result.add(db.getHandleFromId(row[0]))
  return result

proc getFollowingAsIDQuick*(db: DbConn, user: string, limit = 20): seq[string] =
  ## Returns a set of IDs that a specific user follows
  for row in db.getAllRows(sql"SELECT following FROM follows WHERE follower = ? AND approved = true LIMIT ?;", user, $limit):
    result.add(row[0])
  return result

proc getFollowingQuick*(db: DbConn, user: string, limit = 20): seq[string] =
  ## Returns a set of handles that a specific user follows
  for row in db.getAllRows(sql"SELECT following FROM follows WHERE follower = ? AND approved = true LIMIT ?;", user, $limit):
    result.add(db.getHandleFromId(row[0]))
  return result

proc getFollowers*(db: DbConn, user: string): seq[User] =
  ## Returns a set of User objects that follow a specific usr
  for row in db.getAllRows(sql"SELECT follower FROM follows WHERE following = ? AND approved = true;", user):
    result.add(db.getUserById(row[0]))
  return result

proc getFollowing*(db: DbConn, user: string): seq[User] =
  ## Returns a set of User objects that a specific user follows
  for row in db.getAllRows(sql"SELECT following FROM follows WHERE follower = ? AND approved = true;", user):
    result.add(db.getUserById(row[0]))
  return result

proc getFollowersCount*(db: DbConn, user: string): int =
  ## Returns how many people follow this user in a number
  return len(db.getAllRows(sql"SELECT approved FROM follows WHERE following = ? AND approved = true;", user))

proc getFollowingCount*(db: DbConn, user: string): int =
  ## Returns how many people this user follows in a number
  return len(db.getAllRows(sql"SELECT approved FROM follows WHERE follower = ? AND approved = true;", user))

proc getFollowReqCount*(db: DbConn, user: string): int =
  ## Returns how many pending follow requests a user has.
  return len(db.getAllRows(sql"SELECT approved FROM follows WHERE following = ? AND approved = false;", user))
  
type
  FollowStatus* = enum
    NoFollowRequest, PendingFollowRequest, AcceptedFollowRequest

proc getFollowStatus*(db: DbConn, follower, following: string): FollowStatus =
  let row = db.getRow(sql"SELECT approved FROM follows WHERE follower = ? AND following = ?;", follower, following)

  # It's small details like these that break the database logic.
  # You'd expect getRow() to return booleans like this: "true" or "false"
  # But no, it does "t" or "f" which, std/strutil's parseBool() can't handle
  # Thankfully, i've been through this rigamarole before,
  # so i already knew boolean handling was garbage
  if row == @["f"]: return PendingFollowRequest
  if row == @["t"]: return AcceptedFollowRequest
  return NoFollowRequest

proc followUser*(db: DbConn, follower, following: string, approved: bool = true) =
  ## Follows a user (THEY ALL MUST BE IN IDS)
  if not db.userIdExists(follower) or not db.userIdExists(following):
    return # Since users don't exist, we just leave.

  if db.getFollowStatus(follower, following) != NoFollowRequest:
    # Follow request already exists and is either pending or accepted.
    # In that case, just return.
    return
  
  db.exec(
    sql"INSERT INTO follows VALUES (?, ?, ?)",
    follower, following, $approved
  )

proc unfollowUser*(db: DbConn, follower, following: string) =
  ## Unfollows a user
  if not db.userIdExists(follower) or not db.userIdExists(following):
    return # Since users don't exist, we just leave.

  db.exec(
    sql"DELETE FROM follows WHERE follower = ? AND following = ?;",
    follower, following
  )

proc getHomeTimeline*(db: DbConn, user: string, limit: var int = 20): seq[string] =
  ## Returns a list of IDs to posts sent by users that `user` follows or in hashtags that `user` follows.
  # Let's see who this user follows 
  var
    following = db.getFollowingAsIDQuick(user, limit)
    followingTags = db.getTagsFollowedByUser(user, limit)
  
  # First we check to see if the limit is realistic
  # (ie. do we have enough posts to fill it)
  # If not then we just reset the limit to something sane.

  # Note: Due to a circular dependency on posts, we have to use this
  # Instead of calling getNumTotalPosts()
  var t_limit: int = 0
  for x in db.getAllRows(sql("SELECT 0 FROM posts;")):
      inc(t_limit)

  if limit > t_limit:
    limit = t_limit

  # We will start by fetching X number of posts from the db
  # (where X is the limit, oh and the order is chronological, according to *creation* date.)
  # And then checking if its creator was followed or if it has a hashtag we follow.
  #
  # This seemed like the best solution at the time given the circumstances
  # But if it isn't then whoopsie! We will make another one!
  # TODO: Help.
  var
    last_date = now().utc
    flag = false
  while len(result) < limit and flag == false:
    for row in db.getAllRows(sql"SELECT id,sender,written FROM posts WHERE date(written) >= ? ORDER BY written ASC LIMIT ?", toDbString(last_date), $limit):
      if row[1] in following:
        result.add row[0]
        continue
      
      let tags = db.getPostTags(row[0])
      for tag in followingTags:
        if tag in tags:
          result.add row[0]
          continue
    flag = true
    result = result.deduplicate()
  
  # TODO: This does not include posts that have boosts... Too bad!
  return result

proc getTagTimeline*(db: DbConn, tag: string, limit: var int = 20, local = true, remote = true): seq[string] =
  ## Returns a list of IDs to posts in a hashtag.
  return result

## Test suite!
#[

# TODO: This code uses the old newPost proc, maybe make sure to migrate it properly to the new one? (Previously named newPostX)

when isMainModule:
  import quark/[db, users, posts]
  import pothole/[conf, database]
  var config = setup(getConfigFilename())
  var deebee = setup(
    config.getDbName(),
    config.getDbUser(),
    config.getDbHost(),
    config.getDbPass()
  )

  var
    userA = newUser("a", true, "a") # Home timeline user
    niceGuy = newUser("nice", true, "") # Followed user, followed hashtag
    rudeGuy = newUser("rude", true, "") # Followed user, unfollowed hashtag

    postB = newPost(niceGuy.id, @[text("Badabing badaboom!"), hashtag("followed")]) # Followed user, followed hashtag
    postC = newPost(niceGuy.id, @[text("Badabing badaboom Electric boogaloo!"), hashtag("unfollowed")]) # Followed user, unfollowed hashtag
    postD = newPost(rudeGuy.id, @[text("Badabing badaboom Electric Electric boogaloo!"), hashtag("followed")]) # Unfollowed user, followed hashtag
    postE = newPost(rudeGuy.id, @[text("Badabing badaboom Electric Electric II Boogaloo??"), hashtag("unfollowed")]) # Unfollowed user, unfollowed hashtag

  deebee.addUser(userA)
  deebee.addUser(niceGuy)
  deebee.addUser(rudeGuy)
  deebee.followUser(userA.id, niceGuy.id)
  if not deebee.tagExists("followed"):
    deebee.createTag("followed")
  deebee.followTag("followed", userA.id)

  deebee.addPost(postB)
  deebee.addPost(postC)
  deebee.addPost(postD)
  deebee.addPost(postE)

  var limit = 4
  let home = deebee.getHomeTimeline(userA.id, limit)
  echo home
  for post in home:
    if post == postB.id:
      echo "found: Followed user, followed hashtag"
    elif post == postC.id:
      echo "found: Followed user, unfollowed hashtag"
    elif post == postD.id:
      echo "found: Unfollowed user, followed hashtag"
    elif post == postE.id:
      echo "found: Unfollowed user, unfollowed hashtag"

  assert postB.id in home, "Failed test: Followed user, followed hashtag"
  assert postC.id in home, "Failed test: Followed user, unfollowed hashtag"
  assert postD.id in home, "Failed test: Unfollowed user, followed hashtag"
  assert postE.id notin home, "Failed test: Unfollowed user, unfollowed hashtag"
]#