* Tags
* Parameters
* Files

* import v0 orders
* perf logger - when enabled, log every time a linear scan is done over a large array (>100 elements) where we don't expect to process most of them
* Order Items
* Make order info private when logged out
* Projects: steps - progress bars, due dates
* slimselect: typing while focused should open, search
* List pages for items with children should have arrows for expanding
* Improve layout of info pages
* External links should use target="_blank"
* Deduplicate Mfr/dist relations
* Improve search syntax
* Add CSS light theme
* Figure out automatic dark theme detection
* Cost currencies
* slimselect: Automatically compute the end year based on the current time
* Keyboard shortcuts
* recently modified items on landing page
* memory status on landing page
* git status on landing page
* automated git commit/push


# Search syntax brainstorm area
`or`
union (default is for multiple subqueries to be intersection / "and")

`()`
grouping (for use with `or`)

`"quoted string"`
exact word match

`{500 <= R <= 1k}`
parameter search by symbol

`{ @abs.vcc = 5 timing.pd < 10n }`
parameter search using parameter IDs, condition restrictions

`#tag`
tag search

`mfr:asdf`
ID search

- Ignore underscores and formatting symbols when searching by name

# Parameter Brainstorm Area

Need a way to specify overbar, subscript formatting.  Maybe greek/special symbols too.

### Parameter Info:
* ID - e.g. abs.vcc
* Group - Absolute maximums, recommended operating conditions, thermal characteristics, etc.
* Symbol - Vgs(th), Vcc etc.
* Input - useful for e.g. tpd
* Output - useful for e.g. tpd
* Description - Gate threshold voltage, Supply voltage, etc.
* Unit - V, A, ohm, etc.
* bidirectional - enable +/- prefix on numeric values

### Parameter Data:
* Parameter info index
* Conditions - Index of another set of parameter data indicating the conditions under which this parameter is valid - may be an intrusive linked list
* Minimum (Numeric)
* Nominal (Numeric)
* Maximum (Numeric)
* Minimum (Text)
* Nominal (Text)
* Maximum (Text)

### Part Parameters:
* List of parameter indices that apply to a particular part

### Parameter Template:
* ID - e.g. transistor
* parent template - to allow extension
* List of paramet data indices in the template
