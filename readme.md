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
A part is a fungible class of items which you may or may not have in your inventory.

A part may be associated with a manufacturer.  Each manufacturer has a unique ID and various metadata may optionally be recorded about individual manufacturers.
Each part has an ID, which must be unique among all parts with the same manufacturer (or among all parts without any manufacturer, if the part has no manufacturer).
A part may also have an associated package.  Each package can be associated with a manufacturer, and each package has a unique ID among all packages with the same manufacturer (or all parts without any manufacturer).

Parts may have a parent part, and can inherit any fields or parameters of the parent if they are not overridden in the child part.  For example, you might create a generic `74x14` part,
which then has a `74HC14` child, and a `SN74HC14N` child of that that adds the `DIP-14` package and the `TI` manufacturer.

Tags can be applied to parts to group them in ways where a parent/child relationship won't work.  e.g. a `RoHS` tag for lead-free parts.  Tags can have a parent, and applying a tag to a part will also cause that part to have all parent tags.  e.g. if the `BJT` tag for bipolar transistors has a parent `Transistor` tag, then parts tagged with `BJT` will automatically also be tagged with `Transistor`.

## Locations
A location is a named place where parts can be kept in inventory.
Locations may have a parent, e.g. for parts organizers that have a grid of sub-locations.
Each location must have an ID that's unique among all other locations.

## Orders
Orders represent changes in inventory quantities in any number of locations, for any number of parts.
They may literally be orders from a distributor, or they may record the date that a quantity of parts were used, or they may simply be organizational: moving parts from one location to another, accounting for lost parts, etc.

Orders can be in one of several states:
* Preparing (not yet submitted/purchased; may be cancelled)
* Waiting (submitted/purchased/shipped)
* Arrived
* Complete (unboxed)
* Cancelled
* BOM (for project documentation only)

The current inventory levels for each part and contents of each location are computed automatically based on order history.  Orders that are in the "Waiting" or "Arrived" states will be accounted for separately; additions show as "on order" and subtractions show as "reserved".  Orders in the "Preparing", "Cancelled", or "BOM" states will not contribute towards inventory at all.

When viewed in guest mode, only orders in the BOM state will be visible.

## Projects
Projects are used to group orders for a particular purpose.

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
