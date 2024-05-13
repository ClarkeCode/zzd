const std = @import("std");
const strutil = @import("strutil.zig");

const NumericRepresentationMode = enum {
	Hexadecimal,
	HexadecimalUpper,
	Binary,
};

const HexdumpOptions = struct {
	bytesPerLine: usize = 16,
	bytesPerGroup: usize = 2,
	unprintableDefaultChar: u8 = '.',
	numericRepresentationMode: NumericRepresentationMode = .Hexadecimal,
	bytesToProcess: usize = std.math.maxInt(usize),
	showHelpMessage: bool = false,
};

fn hexdump(sequence: []const u8, options: HexdumpOptions) !void {
	const stdout_file = std.io.getStdOut().writer();
	var bw = std.io.bufferedWriter(stdout_file);
	const stdout = bw.writer();

	std.debug.assert(options.bytesPerLine > 0);
	std.debug.assert(options.bytesPerGroup > 0);

	var offset: usize = 0;
	while (offset < sequence.len) : (offset += options.bytesPerLine) {
		//Print line number
		try stdout.print("{x:0>8}: ", .{offset});

		//Print numeric representation
		const line = sequence[offset..@min(offset + options.bytesPerLine, sequence.len)];
		var byteInLine: usize = 0;
		for (line) |byte| {
			if (byteInLine == options.bytesPerGroup) {
				try stdout.print(" ", .{});
				byteInLine %= options.bytesPerGroup;
			}

			switch (options.numericRepresentationMode) {
				.Hexadecimal =>      try stdout.print("{x:0>2}", .{byte}),
				.HexadecimalUpper => try stdout.print("{X:0>2}", .{byte}),
				.Binary =>           try stdout.print("{b:0>8}", .{byte}),
			}
			// try stdout.print(formatters[0], .{byte});
			byteInLine += 1;
		}

		//Ensure proper spacing between representations
		if (line.len < options.bytesPerLine) {
			const diff: usize = options.bytesPerLine - line.len;
			const spacesPerByte: usize = switch (options.numericRepresentationMode) {
				.Hexadecimal, .HexadecimalUpper => 2,
				.Binary => 8
			};

			for (0..spacesPerByte*diff + diff/options.bytesPerGroup) |_| {
				try stdout.print(" ", .{});
			}
		}
		try stdout.print("  ", .{});
		
		//Print graphical representation
		for (line) |byte| {
			const printChar = switch (byte) {
				0...31, 127...255 => options.unprintableDefaultChar,
				' '...'~' => byte, //ASCII printable range
			};
			try stdout.print("{c}", .{printChar});
		}
		try stdout.print("\n", .{});
	}

	try bw.flush();
}

///Returned buffer is allocated, responsibility of caller to free
fn readInfileToBuffer(allocator: std.mem.Allocator, fileName: []const u8) ![]u8 {
	var buff: []u8 = undefined;
	//If the name is '-', input is from stdin
	if (std.mem.eql(u8, "-", fileName)) {
		buff = try std.io.getStdIn().readToEndAlloc(allocator, std.math.maxInt(usize));
	}
	else {
		var file = try std.fs.cwd().openFile(fileName, .{});
		defer file.close();
		const fsize = (try file.stat()).size;
		buff = try file.readToEndAlloc(allocator, fsize);
	}

	return buff;
}

fn showHelp() void {
	const stderr = std.io.getStdErr().writer();
	stderr.print("Usage:\n\tzzd [options] [infile]\n\nOptions:\n", .{}) catch return;
	const formatstr = " " ** 4 ++ "{s:<14}{s}\n";
	stderr.print(formatstr, .{"-b",       "Binary digit dump. Default is Hexadecimal."}) catch return;
	stderr.print(formatstr, .{"-c bytes", "Format <bytes> per line. Default is 16."}) catch return;
	stderr.print(formatstr, .{"-g bytes", "Number of bytes per group. Default is 2."}) catch return;
	stderr.print(formatstr, .{"-h",       "Show this help message."}) catch return;
	stderr.print(formatstr, .{"-l len",   "Stop output after <len> bytes."}) catch return;
	stderr.print(formatstr, .{"-u",       "Use upper-case for hex letters."}) catch return;
}

const ProcessedCmdline = struct {
	infile: ?[]const u8 = null,
	outfile: ?[]const u8 = null,
	options: HexdumpOptions = .{}
};
fn processCommandlineArgs() ProcessedCmdline {
	const streq = strutil.streq;
	var result: ProcessedCmdline = .{};
	var specifiedBytesPerLine = false;
	var specifiedBytesPerGroup = false;
	var index: usize = 1;
	while (index < std.os.argv.len) : (index += 1) {
		const slice = strutil.strNulltermToSlice(std.os.argv[index]);

		if (streq("-u", slice)) {
			result.options.numericRepresentationMode = .HexadecimalUpper;
		}
		else if (streq("-b", slice) or streq("-bits", slice)) {
			result.options.numericRepresentationMode = .Binary;
		}
		else if (streq("-h", slice) or streq("-help", slice)) {
			result.options.showHelpMessage = true;
		}

		else if (streq("-c", slice) or streq("-cols", slice)) {
			if (index + 1 < std.os.argv.len) {
				result.options.bytesPerLine = std.fmt.parseUnsigned(usize, strutil.strNulltermToSlice(std.os.argv[index+1]), 0) catch 16;
			}
			specifiedBytesPerLine = true;
			index += 1;
		}
		else if (streq("-g", slice) or streq("-groupsize", slice)) {
			if (index + 1 < std.os.argv.len) {
				result.options.bytesPerGroup = std.fmt.parseUnsigned(usize, strutil.strNulltermToSlice(std.os.argv[index+1]), 0) catch 2;
			}
			specifiedBytesPerGroup = true;
			index += 1;
		}
		else if (streq("-l", slice) or streq("-len", slice)) {
			if (index + 1 < std.os.argv.len) {
				result.options.bytesToProcess = std.fmt.parseUnsigned(usize, strutil.strNulltermToSlice(std.os.argv[index+1]), 0) catch std.math.maxInt(usize);
			}
			index += 1;
		}
		else if (result.infile == null) {
			result.infile = slice;
		}
		else {
			result.outfile = slice;
		}
	}

	if (!specifiedBytesPerLine) {
		result.options.bytesPerLine = switch (result.options.numericRepresentationMode) {
			.Hexadecimal, .HexadecimalUpper => 16,
			.Binary => 6,
		};
	}
	//Use default groupings if the bytes-per-line has not been specified
	if (!specifiedBytesPerGroup) {
		result.options.bytesPerGroup = switch (result.options.numericRepresentationMode) {
			.Hexadecimal, .HexadecimalUpper => 2,
			.Binary => 1,
		};
	}
	return result;
}

pub fn main() !void {
	const result = processCommandlineArgs();

	if (result.infile == null or result.options.showHelpMessage) {
		showHelp();
		return;
	}
 
	var gpa = std.heap.GeneralPurposeAllocator(.{}){};
	const allocator = gpa.allocator();
	var buffer: []u8 = try readInfileToBuffer(allocator, result.infile.?);
	defer allocator.free(buffer);

	try hexdump(buffer[0..@min(buffer.len, result.options.bytesToProcess)], result.options);
}

test "simple test" {
	var list = std.ArrayList(i32).init(std.testing.allocator);
	defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
	try list.append(42);
	try std.testing.expectEqual(@as(i32, 42), list.pop());
}
