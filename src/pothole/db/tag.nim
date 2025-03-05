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
# quark/db/tag.nim:
## This module contains all database logic for handling hashtags!
## Including creation, retrieval, checking, updating and deletion
import quark/private/database, quark/shared, std/times
export shared, times

proc tagExists*(db: DbConn, tag: string): bool =
  return has(db.getRow(sql"SELECT trendable FROM tag WHERE name = ?;", tag))

proc getTagUrl*(db: DbConn, tag: string): string =
  return db.getRow(sql"SELECT url FROM tag WHERE name = ?;", tag)[0]

proc userFollowsTag*(db: DbConn, tag, user: string): bool =
  ## Returns true if a user (supplied by ID) follows a hashtag
  return has(db.getRow(sql"SELECT following FROM tag_follows WHERE follower = ? AND following = ?;", user, tag))

proc getTagsFollowedByUser*(db: DbConn, user: string, limit = 100): seq[string] =
  for i in db.getAllRows(sql"SELECT following FROM tag_follows WHERE follower = ? LIMIT ?;", user, $(limit)):
    result.add(i[0])
  return result

proc followTag*(db: DbConn, tag, user: string) =
  db.exec(
    sql"INSERT INTO tag_follows VALUES (?,?);",
    user, tag
  )

proc unfollowTag*(db: DbConn, tag, user: string) =
  db.exec(
    sql"DELETE FROM tag_follows WHERE follower = ? AND following = ?;",
    user, tag
  )

proc createTag*(db: DbConn, name: string, url = "", desc = "", trendable = true, usable = true, requires_review = false, system = false) =
  ## Creates a new tag object in the database and returns the ID associated with it.
  db.exec(
    sql"INSERT INTO tag VALUES (?,?,?,?,?,?,?);",
    name, url, desc, trendable, usable, requires_review, system
  )

proc hashtag*(name: string, date = now().utc): PostContent =
  return PostContent(
    kind: Tag, tag_used: name, tag_date: date
  )

# For the next three procs
# Given that this API is called on startup by a staggering number of clients,
# The top priority was to strike a balance between performance and storage costs
# If I wanted absolute performance, I would have embedded the sender ID of each account into the posts_tag table.
# If I wanted as little as storage cost, I would have had *no posts_tag table* at all
# Anyway, the game plan is that posts_tag records date info for every hashtag in every post.
# And we use that not just to return the number of unique posts, but also we use an extra db call to
# figure out the sender and return the number of unique accounts

proc getTagUsagePostNum*(db: DbConn, tag: string, days = 2): seq[int] =
  ## Returns the number of posts using a tag in the past couple X days.
  for i in countup(0,days - 1):
    var x = 0
    
    # TODO: This feels a bit inefficient... Could we optimize it?
    for row in db.getAllRows(
      sql"SELECT 0 FROM posts_tag WHERE tag = ? AND use_date = ?;",
      tag, getDateStr(now().utc - i.days)
    ):
      inc x
    
    result.add(x)
  return result

proc getTagUsageUserNum*(db: DbConn, tag: string, days = 2): seq[int] =
  ## Returns the number of accounts using a tag in the past couple X days
  ## 
  for i in countup(0,days - 1):
    var x = 0

    # TODO: This feels a bit inefficient... Could we optimize it?
    for row in db.getAllRows(
      sql"SELECT DISTINCT ON (sender) 0 FROM posts_tag WHERE tag = ? AND use_date = ?;",
      tag, getDateStr(now().utc - i.days)
    ):
      inc x
    
    result.add(x)
  return result

proc getPostTags*(db: DbConn, post: string): seq[string] =
  for row in db.getAllRows(sql"SELECT tag FROM posts_tag WHERE pid = ?;", post):
    result.add(row[0])
  return result

proc postHasTag*(db: DbConn, post, tag: string): bool =
  return has(db.getRow(sql"SELECT 0 FROM posts_tag WHERE pid = ? AND tag = ?;", post, tag))

proc getTagUsageDays*(days = 2): seq[int64] =
  ## Used only for the Tag ApiEntity
  for i in countup(0,days - 1):
    result.add(toUnix(toTime(now().utc - i.days)))

# Test suite:
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
    userA = newUser("a", true, "")
    userB = newUser("b", true, "")
    postA = newPost(userA.id, @[text("Badabing badaboom!"), hashtag("hi")])
    postB = newPost(userA.id, @[text("Badabing badaboom 2!"), hashtag("hi")])
    postC = newPost(userB.id, @[text("Badabing badaboom 3?"), hashtag("hi")])

  deebee.addUser(userA)
  deebee.addUser(userB)
  deebee.addPost(postA)
  deebee.addPost(postB)
  deebee.addPost(postC)
  

  if not deebee.tagExists("hi"):
    deebee.createTag("hi")
  echo deebee.getTagUsagePostNum("hi")
  echo deebee.getTagUsageUserNum("hi")
]#