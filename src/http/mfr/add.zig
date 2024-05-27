pub const validate = @import("add/validate.zig");
pub const validate_additional_name = @import("add/validate_additional_name.zig");
pub const validate_relation = @import("add/validate_relation.zig");

pub fn get(session: ?Session, req: *http.Request) !void {
    const id = (try req.get_path_param("mfr")) orelse "";
    const now = std.time.milliTimestamp();
    const mfr = Manufacturer.init_empty(id, now);
    try render(session, req, mfr, &.{}, .add);
}

const log = std.log.scoped(.@"http.mfr");

const render = @import("../mfr.zig").render;

const Manufacturer = DB.Manufacturer;
const DB = @import("../../DB.zig");
const Session = @import("../../Session.zig");
const sort = @import("../../sort.zig");
const slimselect = @import("../slimselect.zig");
const http = @import("http");
const std = @import("std");
