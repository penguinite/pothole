# Copyright © Leo Gavilieau 2023 <xmoo@privacyrequired.com>
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
# debug.nim:
## Common procedures for debugging. This is only useful for creating
## fake users and fake posts (for testing)
import std/[tables, os]
import quark/[users, posts]
from db_connector/db_postgres import DbConn, open
{.define: iniplusCheckmaps.}
import rng, iniplus

const userData* = @[
  ("scout", "Jeremy", "All the ladies love me!"),
  ("soldier", "Jane Doe", "GOD BLESS AMERICA"),
  ("pyro", "pyro", "Apparently, this user prefers to keep an air of mystery about them."),
  ("demoman", "Tavish Finnegan DeGroo", "God bless Scotland!"),
  ("heavy", "Mikhail", "Craving sandvich."),
  ("engineer", "Dell Conagher", "I solve practical problems and I have 11 PhDs."),
  ("medic", "Ludwig Humboldt", "Professional doctor who previously had a medical license."),
  ("sniper", "Mundy", "A professional with standards. NOT A MURDERER"),
  ("spy", "spy", "Scout is a virgin")
]

const fakeStatuses* = @[
  "Hello World!", 
  "I hate writing database stuff...", 
  "I like to keep an air of mystery around me", 
  "Here's a cute picture of a cat! (I don't know how to use this app, I am sorry if the picture does not appear)", 
  "Cannabis abyss and Pot hole mean the same thing.", 
  "Woke up, had some coffee, hit a car during my commute to work, escaped masterfully.\n\nHow was your day?",
  "\"It's GNU/Linux\"\n\"It's just Linux\"\n\nThey don't know that it's...\nwhatever the fuck you want to call it\nlife is meaningless, we're all gonna die",
  "The FBI looking at me googling \"How to destroy children\": 😨\nThe FBI looking at me after clarifying im programming in C: 😇",
  "When god falls, I will find the spigot upon which they meter out grace and smash it permanently open.",
  "No matter how much I ferventley pray, god never reveals why they deeply dislike me.",
  "Always store confidential data in /dev/urandom for safety!\nNo one can recover data from /dev/urandom",
  "If you want a job, write software.\nIf you want a career, write a package manager.",
  "Lorem Ipsum Dolor Sit Amet",
  "It does not matter how slow you go as long as you do not stop.",
  "Sometimes the most impressive things are the simplest things",
  "systemd introduces new tool called systemd-lifed\n\nsimply create a config file and systemd will possess your body and take cake of your own life for you.",
  "Hello from potholepkg!",
  "Consider: inhaling spaghetti",
  "Man. I love AI lawyers so much.\n\"Mr. Doe, how do you justify these grave crimes?\"\n\"Uh... Connection timed out?\"\n",
  "It is hell here!",
  "Anna is eating a canary",
  "He says he is a model but really he is a priest",
  "I don't love you, I only love mayonnaise.",
  "He informed the jury that he was too pretty to go to jail.",
  "THERE IS A PROBLEM! He uh... wants to come with his cow.",
  "Jeg er osten",
  "I thought it was an apple store but they only sold computers.",
  "What does 8008 look like on a calculator?",
  "I am going out for a walk with my lawyer",
  "Excuse me! I have become an apple!",
  "DE KOMMER IND LIGE NU! IGENNEM VINDUERNE!",
  "Hello World! -- penguinite!",
  """
<Guo_Si> Hey, you know what sucks?
<TheXPhial> vaccuums
<Guo_Si> Hey, you know what sucks in a metaphorical sense?
<TheXPhial> black holes
<Guo_Si> Hey, you know what just isn't cool?
<TheXPhial> lava?
  """,
  """
<tatclass> YOU ALL SUCK DICK
<tatclass> er.
<tatclass> hi.
<andy\code> A common typo.
<tatclass> the keys are like right next to each other.
  """,
  """
<Khassaki> HI EVERYBODY!!!!!!!!!!
<Judge-Mental> try pressing the the Caps Lock key
<Khassaki> O THANKS!!! ITS SO MUCH EASIER TO WRITE NOW!!!!!!!
<Judge-Mental> fuck me
  """,
  "I gotta go.  There's a dude next to me and he's watching me type, which is sort of starting to creep me out.  Yes dude next to me, I mean you.",
  "I hated going to weddings. All the grandmas would poke me saying \"You're next\". They stopped that when I started doing it to them at funerals.",
  """
<reo4k> just type /quit whoever, and it'll quit them from irc
* luckyb1tch has quit IRC (r`heaven)
* r3devl has quit IRC (r`heaven)
* sasopi has quit IRC (r`heaven)
* phhhfft has quit IRC (r`heaven)
* blackersnake has quit IRC (r`heaven)
<ibaN`reo4k[ex]> that's gotta hurt
<r`heaven> :(
  """,
  "* Porter is now known as PorterWITHGIRLFRIENDWHOISHOT\n<Strayed> he shot his girlfriend?",
  "Mike3285: wtf is a palindrome\nMaroonSand: no its not dude",
  "I'm my own worst enemy but the enemy of my enemy is my friend so I'm also my own best friend it's just basic math"
]

const reactions* = @[
  # Some sample reactions.
  "happy","sad","angry","disgusted","favorite"
]

const boosts* = @[
  # Some sample boost levels.
  "all","followers","local","private"
]

proc genFakePosts*(): seq[Post] =
  ## Creates a couple of fake posts.
  for txt in fakeStatuses:
    result.add(
      newPost(
        sender = sample(userData)[0],
        content = @[text(txt)]
      )
    )
  return result

proc genRandomHandles*(): seq[string] =
  ## Generates a couple of random handles (not users)
  ## Used in genFakeReactions() and genFakeBoosts()
  for i in 0..rand(high(userData)):
    result.add(sample(userData)[0])
  return result

proc genFakeReactions*(): Table[string, seq[string]] =
  ## Creates a couple of fake reactions.
  for i in 0..rand(25):
    let reaction = sample(reactions)
    if not result.hasKey(reaction):
      result[reaction] = genRandomHandles()
  return result

proc genFakeBoosts*(): Table[string, seq[string]] = 
  ## Generates a couple of fake boosts
  for i in 0..rand(25):
    let boost = sample(boosts)
    if not result.hasKey(boost):
      result[boost] = genRandomHandles()
  return result

proc genFakeUsers*(): seq[User] =
  ## Generates a couple of fake users
  for userData in userData:
    var user = newUser(userData[0], true)
    user.id = userData[0]
    user.name = userData[1]
    user.bio = userData[2]
    user.is_frozen = true
    user.password = "DISABLED_FOREVER"
    result.add(user)
  return result

proc connectToDb*(): DbConn =
  ## Uses default values to connect to a database, suitable for tests.
  proc getFromEnvOrDefault(env, default: string): string =
    if existsEnv(env):
      return getEnv(env)
    return default

  return open(
    getFromEnvOrDefault("PHDB_HOST","127.0.0.1:5432"),
    getFromEnvOrDefault("PHB_USER", "pothole"),
    getFromEnvOrDefault("PHDB_PASS", "SOMETHING_SECRET"),
    getFromEnvOrDefault("PHDB_NAME", "pothole")
  )

proc testGuard*(section, name: string) =
  ## This is a poor guard against testament running tests multiple times.
  const fn = ".testGuardTmpDELETEME"

  var cnf: ConfigTable
  if fileExists(fn):
    cnf = parseString(readFile(fn))
  
  if cnf.exists(section, name):
    quit(0)
  else:
    cnf.setKey(section, name, newCValue(true))
    writeFile(fn, toString(cnf))