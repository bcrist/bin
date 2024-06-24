# Bin: Inventory Tracking System

Bin is a tool for managing your collection of electronic parts, including purchases, inventory levels, locations, project BOMs, datasheets, and other metadata.

Although Bin was designed with electronics in mind, it may also be useful for other hobbies that require keeping track of a lot of individual items.

The primary interface to Bin is through a web browser.  Bin requires no installation, and by default can be accessed at [localhost:16777] as soon as it has started.

Bin's database and all configuration data are stored in text files, using s-expressions.  This means you can use git (or another VCS) to easily back up, track history, and sync the database across different machines.  When running, the entire database is loaded into memory, and external changes to the files on disk may be lost.  Changes made through the web interface will be written to disk after a short delay (the exact duration can be configured).

# Windows Quickstart

1. Download the latest release and extract it to a location of your choosing.
1. Edit the `bin.conf` file to specify the location you want to store your database, and change the default password if you intend to host Bin over the internet.  Note the `bin.conf` file must always be in the same directory as the `bin.exe` file.
1. Run `bin.exe`
1. Open `localhost:16777` in a browser to start using Bin!

# Building from Source (Linux/Windows/Mac)

Building Bin requires only a recent [Zig compiler](https://ziglang.org/download/).  Clone the repo and run `zig build bin` to build and run Bin.  After running the first time, a default config file should be created at `zig-out/bin/bin.conf` but you may need to edit it and restart Bin to add a user.  See the releases page for an example.





## Parts
TODO

## Orders
TODO

## Projects
TODO

## Searching
TODO


# Implementation Details
* Bin strives to avoid as much client-side javascript as possible by using [HTMX](https://htmx.org)
* HTML templating is performed with [zkittle](https://github.com/bcrist/zkittle)
* The HTTP server is [sHiTTiP](https://github.com/bcrist/shittip), which uses [dizzy](https://github.com/bcrist/dizzy) for request handler dependency injection.
* Date/Time handling is provided by [tempora](https://github.com/bcrist/tempora)
* S-expression serialization and parsing is performed with [Zig-SX](https://github.com/bcrist/Zig-SX)

# Alternatives
There's a lot of inventory management software out there, and many of them provide features that Bin lacks, but this is an area where everyone's needs are different.  I wasn't happy with any of the existing options that I tried, so I made my own, but you may want to look at some of these projects/products as well:

* https://partsbox.com/
* https://www.partkeepr.org/
* https://binner.io/
* https://bomist.com/
* https://github.com/Part-DB/Part-DB-server
* https://partsinplace.com/
* https://www.minimrp.com/
* https://homebox.sysadminsmedia.com/

Many of the above are paid (or subscription-based) products, and most of the open-source options are based on PHP or other complicated and bloated web stacks.  Of them, Homebox is probably closest to Bin philosophically, but it's designed people in IT rather than EE.