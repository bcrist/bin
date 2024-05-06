# Bin: Inventory Tracking System

Bin is a tool for managing your collection of electronic parts, including purchases, inventory levels, locations, project BOMs, datasheets, and other metadata.

Although Bin was designed with electronics in mind, it may also be useful for other hobbies that require keeping track of a lot of individual items.

The primary interface to Bin is through a web browser.  Bin requires no installation, and by default can be accessed at [localhost:16777] as soon as it has started.

Bin's database and all configuration data are stored in text files.  When running, the entire database is loaded into memory, and changes to the files on disk may be lost.  Changes made through the web interface will be written to disk immediately.  The database can easily be synced across machines by storing it in a git repo (either a fork of this one including the application itself, or a separate repo containing just the data).
