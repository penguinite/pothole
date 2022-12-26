# Copyright © Pothole Project 2022
# Licensed under the AGPL version 3 or later.

# From Pothole
import lib
import conf
import routes
import db

# From standard library
import std/[strutils, parsecfg, os]

# From nimble
import prologue


echo("Pothole version ")
echo("Copyright © Louie Quartz 2022.")
echo("Licensed under the GNU Affero General Public License version 3 or later")


var configfile: string = "pothole.conf"
if existsEnv("POTHOLE_CONFIG"):
  configfile = getEnv("POTHOLE_CONFIG")

echo("Config file used: ", configfile)

if conf.setup(loadConfig(configfile)) == false:
  error("Failed to load configuration file!", "main.startup")

# Now... We have to check if our required configuration
# options are actually there
for x in lib.requiredConfigOptions:
  var list = x.split(":")
  if exists(list[0],list[1]):
    continue
  else:
    error("Missing key " & list[1] & " in section " & list[0], "main.startup")

# Catch Ctrl+C
setControlCHook(lib.exit)

# Initialize the database
echo("Initializing database")
db.init()


# Fetch port from config file
var realport = Port(3500)
if exists("web","port"):
  realport = Port(parseInt(get("web","port")))

let settings = newSettings(appName = "Pothole",port = realport)

var app = newApp(settings = settings)

app.addRoute("/", routes.index,@[HttpGet, HttpPost])

while isMainModule:
  app.run()

exit()





# And we all *shut* down...