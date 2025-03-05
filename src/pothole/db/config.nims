switch("path","./../")
switch("stackTrace","on") # For better debugging
switch("mm", "orc") # Required by mummy
switch("d", "useMalloc") # Required for fixing memory leak.
switch("threads","on") # Required by mummy