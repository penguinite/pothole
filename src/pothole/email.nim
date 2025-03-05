# Copyright © penguinite 2024-2025 <penguinite@tuta.io>
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
# email.nim:
## Functions for working with email. (Primarily sending an email)

{.define: ssl.}
import std/strutils
import pothole/shared
import smtp, iniplus


proc sendEmail(config: ConfigTable, address: string, message: Message) =
  ## Sends an email to an address containing a message.
  ## This is basically just a helpful wrapper procedure around the smtp library
  if not config.getBoolOrDefault("email", "enabled", false):
    log "sendEmail() called but email hasn't been enabled"
    log "Double check the Pothole configuration file please."
    log "Either you forgot to disable an option ([web] require_verification) or you forgot to enable another one ([email] enabled)"
    return # Return as there is nothing to do.

  let
    ssl = config.getStringOrDefault("email", "ssl", "true").toLower()
    host = config.getString("email","host")
    port = Port(config.getInt("email","port"))
    user = config.getStringOrDefault("email", "user", "")
    pass = config.getStringOrDefault("email", "pass", "")
    fromAddr = config.getString("email", "from")

  var smtp: Smtp
  if ssl == "true":
    smtp = newSmtp(useSsl = true)
  else:
    smtp = newSmtp()
  
  smtp.connect(host, port)
  if ssl == "starttls":
    smtp.startTls()
  
  if user != "" and pass != "":
    smtp.auth(
      user,
      pass
    )

  smtp.sendMail(
    fromAddr,
    @[address], $(message)
  )

proc sendEmailCode*(config: ConfigTable, code, address: string) =
  ## Sends an email for an account verification code.
  if "\n" in address:
    log "Address has newlines in it. We will crash if we send this."
    log "Soooo, we're just not gonna send it."
    return

  config.sendEmail(address,
    createMessage(
      "Verification code for Pothole account",
"""
Your Pothole account has been created! 
But we do need you to verify that this email address is real.

You can do this by simply going to this link:
$#
""" % [code],
      @[address], @[],
    )
  )

  
  

  





