all:
	zig build

clean:
	find zig-cache/ zig-out/ -delete 2> /dev/null