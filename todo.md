* Parts
* Orders
* Projects
* Parameters
* Files

* When IDs change, any data files that reference the old ID need to be re-written, even if they're not modified
* search for locations, packages
* slimselect: Automatically compute the end year based on the current time
* slimselect: typing while focused should open, search
* Don't use slimselect for package/location parents, package mfr, or mfr relation.other - do like for for main search bar
* List pages for items with children should have arrows for expanding
* Improve layout of info pages

* For objects with parent chains, serialize all descendant objects within the same file as the top level one
* Deduplicate Mfr relations
* Part numbers by distributor
* Part tags

* zkittle template fragments
* zkittle vscode fix expression syntax highlighting

* Merging multiple mfrs/locations/etc?
* Keyboard shortcuts
* recently modified items on landing page
* git status on landing page
* automated git commit/push



Search syntax brainstorm area
or - union (default is for multiple subqueries to be intersection / "and")
() - grouping for above
"quoted string" - exact word match
{500 <= R <= 1k} - parameter search by symbol
{ @abs.vcc = 5 timing.pd < 10n } - parameter search using parameter IDs, condition restrictions
#tag - tag search
mfr:asdf - ID search

Ignore underscores and formatting symbols when searching by name




Parameter Brainstorm Area

Need a way to specify overbar, subscript formatting.  Maybe greek/special symbols too.

Parameter Info:
    ID - e.g. abs.vcc
    Group - Absolute maximums, recommended operating conditions, thermal characteristics, etc.
    Symbol - Vgs(th), Vcc etc.
    Input - useful for e.g. tpd
    Output - useful for e.g. tpd
    Description - Gate threshold voltage, Supply voltage, etc.
    Unit - V, A, ohm, etc.
    bidirectional - enable +/- prefix on numeric values

Parameter Data:
    Parameter info index
    Conditions - Index of another set of parameter data indicating the conditions under which this parameter is valid - may be an intrusive linked list
    Minimum (Numeric)
    Nominal (Numeric)
    Maximum (Numeric)
    Minimum (Text)
    Nominal (Text)
    Maximum (Text)

Part Parameters:
    List of parameter indices that apply to a particular part

Parameter Template:
    ID - e.g. transistor
    parent template - to allow extension
    List of paramet data indices in the template
