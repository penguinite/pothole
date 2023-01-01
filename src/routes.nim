# Copyright © Louie Quartz 2022
# Licensed under the AGPL version 3 or later.
#
# Procedures and functions for Prologue routes.
# Storing them in pothole.nim or anywhere else
# would be a disaster.

# From Pothole
#import conf
#import lib
#import data
import db, web, assets,lib

# From standard libraries
from std/strutils import replace, contains

# From Nimble/other sources
import jester

router main:
  get "/":
    resp(web.indexPage())

  get "/users/@user":
    var user = @"user"
    # Assume the client has requested a user by handle
    # Let's do some basic validation first
    if not userHandleExists(user):
      resp(web.errorPage("No user found.",404))
    
    #resp(web.userPage(user))
    resp($getUserByHandle(user))

  get "/css/style.css":
    resp(fetchStatic("style.css"))
      

var potholeRouter* = main