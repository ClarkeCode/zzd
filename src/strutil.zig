const std = @import("std");

fn strlenNullterminated(ntstring: [*:0]u8) usize {
	var offset: usize = 0;
	while (ntstring[offset] != 0) : (offset += 1) {}
	return offset;
}

pub fn strNulltermToSlice(ntstring: [*:0]u8) []const u8 {
	const length = strlenNullterminated(ntstring);
	return ntstring[0..length];
}

pub fn streq(a: []const u8, b: []const u8) bool {
	return std.mem.eql(u8, a, b);
}