/// v0 isn't and was never a full database format; it only exists to be able to import some order data
/// that I compiled manually before starting on Bin, to see how an s-expr based database might look.

pub fn parse_data(db: *DB, reader: *sx.Reader) !void {
    if (try reader.expression("orders")) {
        try parse_orders(db, reader);
        try reader.require_close();
    }
}

fn parse_orders(db: *DB, reader: *sx.Reader) !void {
    const Order_Directive = enum {
        init,
        complete,
        dist,
        stock,
        total,
        project,
    };

    while (try reader.open()) {
        const order = Order.init_empty("", std.time.milliTimestamp());

        while (try reader.open()) {
            switch (try reader.require_any_enum(Order_Directive)) {
                .init => {
                },
                .complete => {
                },
                .dist => {
                },
                .stock => {
                },
                .total => {
                },
                .project => {
                },
            }

            try reader.require_close();
        }

        try reader.require_close();

        const id = order.id; // TODO compute order ID

        const idx = try Order.lookup_or_create(db, id);
        _ = idx;
        // TODO update fields
        // TODO add Order_Items
    }

}

const log = std.log.scoped(.db);

const Order = DB.Order;
const DB = @import("../DB.zig");
const paths = @import("paths.zig");
const sx = @import("sx");
const std = @import("std");
