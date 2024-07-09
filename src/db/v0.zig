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
        var order = Order.init_empty("", std.time.milliTimestamp());
        var project_links = std.ArrayList(Project.Index).init(reader.token.allocator);
        defer project_links.deinit();

        var items = std.ArrayList(Order_Item).init(reader.token.allocator);
        defer items.deinit();

        while (try reader.open()) {
            switch (try reader.require_any_enum(Order_Directive)) {
                .init => {
                    const date_str = try reader.require_any_string();
                    const date = tempora.Date.from_string("Y-M-D", date_str) catch |err| {
                        log.err("Invalid (init) date: {s}", .{ date_str });
                        return err;
                    };

                    order.created_timestamp_ms = date.with_time(.noon).with_offset(0).timestamp_ms();
                    order.modified_timestamp_ms = order.created_timestamp_ms;
                },
                .complete => {
                    const date_str = try reader.require_any_string();
                    const date = tempora.Date.from_string("Y-M-D", date_str) catch |err| {
                        log.err("Invalid (init) date: {s}", .{ date_str });
                        return err;
                    };

                    order.completed_timestamp_ms = date.with_time(.noon).with_offset(0).timestamp_ms();
                    if (order.created_timestamp_ms == 0) {
                        order.created_timestamp_ms = order.completed_timestamp_ms.?;
                        order.modified_timestamp_ms = order.created_timestamp_ms;
                    }
                },
                .dist => {
                    var name = try reader.require_any_string();
                    if (std.ascii.eqlIgnoreCase(name, "ebay")) {
                        name = try reader.require_any_string();
                    }
                    order.dist = try Distributor.lookup_or_create(db, name);
                    order.po = try db.maybe_intern(try reader.any_string());
                },
                .stock => while (try reader.open()) {
                    var item = Order_Item.init_empty();
                    var notes = std.ArrayList(u8).init(reader.token.allocator);
                    defer notes.deinit();

                    if (try reader.string("#")) {
                        while (try reader.any_string()) |note| {
                            if (notes.items.len > 0) try notes.append(' ');
                            try notes.appendSlice(note);
                        }
                    }

                    var mfr_idx: ?Manufacturer.Index = null;
                    if (try reader.any_string()) |mfr_id| {
                        if (mfr_id.len > 0 and !std.mem.eql(u8, mfr_id, "_")) {
                            mfr_idx = try Manufacturer.lookup_or_create(db, mfr_id);
                        }
                    }
                    if (try reader.any_string()) |part_id| {
                        if (part_id.len > 0 and !std.mem.eql(u8, part_id, "_")) {
                            item.part = try Part.lookup_or_create(db, mfr_idx, part_id);
                        }
                    }

                    item.qty = try reader.any_int(i32, 10);
                    item.qty_uncertainty = try reader.any_enum(Order_Item.Quantity_Uncertainty);

                    var check_for_subexpression = true;
                    while (check_for_subexpression) {
                        check_for_subexpression = false;
                        if (try reader.expression("loc")) {
                            const name = try reader.require_any_string();
                            item.loc = try Location.lookup_or_create(db, name);
                            try reader.require_close();
                            check_for_subexpression = true;
                        } else if (try reader.expression("total")) {
                            var amount = try reader.require_any_string();
                            if (std.mem.startsWith(u8, amount, "$")) amount = amount[1..];
                            item.cost_total_hundreths = try costs.decimal_to_hundreths(amount);
                            try reader.require_close();
                            check_for_subexpression = true;
                        } else if (try reader.expression("each")) {
                            var amount = try reader.require_any_string();
                            if (std.mem.startsWith(u8, amount, "$")) amount = amount[1..];
                            item.cost_each_hundreths = try costs.decimal_to_hundreths(amount);
                            try reader.require_close();
                            check_for_subexpression = true;
                        } else if (try reader.expression("note")) {
                            while (try reader.any_string()) |note| {
                                if (notes.items.len > 0) try notes.append(' ');
                                try notes.appendSlice(note);
                            }
                            try reader.require_close();
                            check_for_subexpression = true;
                        }
                    }

                    try reader.require_close();

                    if (notes.items.len > 0) {
                        item.notes = try db.intern(notes.items);
                    }

                    try items.append(item);
                },
                .total => {
                    var amount = try reader.require_any_string();
                    if (std.mem.startsWith(u8, amount, "$")) amount = amount[1..];
                    order.total_cost_hundreths = try costs.decimal_to_hundreths(amount);
                },
                .project => {
                    const name = try reader.require_any_string();
                    try project_links.append(try Project.lookup_or_create(db, name));
                },
            }

            try reader.require_close();
        }

        try reader.require_close();

        const id_date = tempora.Date_Time.With_Offset.from_timestamp_ms(order.created_timestamp_ms, null).dt.date;
        var id_uniquifier: usize = 0;
        var id_buf: [10]u8 = undefined;
        var id: []const u8 = "";
        while (id.len == 0) {
            id = try std.fmt.bufPrint(&id_buf, "{YYMMDD}{d:0>2}", .{ id_date, id_uniquifier });
            id_uniquifier += 1;
            if (Order.maybe_lookup(db, id) != null) id = "";
        }

        const idx = try Order.lookup_or_create(db, id);
        try Order.set_dist(db, idx, order.dist);
        try Order.set_po(db, idx, order.po);
        try Order.set_total_cost_hundreths(db, idx, order.total_cost_hundreths);
        try Order.set_notes(db, idx, order.notes);
        try Order.set_completed_time(db, idx, order.completed_timestamp_ms);
        try Order.set_created_time(db, idx, order.created_timestamp_ms);
        try Order.set_modified_time(db, idx, order.modified_timestamp_ms);

        for (project_links.items) |linked_prj| {
            _ = try Order.Project_Link.lookup_or_create(db, .{
                .order = idx,
                .prj = linked_prj,
            });
        }

        for (0.., items.items) |i, *item| {
            item.order = idx;
            item.ordering = @intCast(i);
            _ = try Order_Item.create(db, item.*);
        }
    }
}

const log = std.log.scoped(.db);

const Location = DB.Location;
const Part = DB.Part;
const Manufacturer = DB.Manufacturer;
const Distributor = DB.Distributor;
const Project = DB.Project;
const Order_Item = DB.Order_Item;
const Order = DB.Order;
const DB = @import("../DB.zig");
const costs = @import("../costs.zig");
const paths = @import("paths.zig");
const tempora = @import("tempora");
const sx = @import("sx");
const std = @import("std");
