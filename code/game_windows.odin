package main

import "core:mem"
import "core:sys/windows"

Byte :: 1
Kilobyte :: 1024 * Byte
Megabyte :: 1024 * Kilobyte
Gigabyte :: 1024 * Megabyte

main :: proc() {

	// NOTE: Allocate
	{
		size := 1 * Gigabyte
		ptr := windows.VirtualAlloc(
			nil,
			cast(uint)size,
			windows.MEM_COMMIT | windows.MEM_RESERVE,
			windows.PAGE_READWRITE,
		)
		assert(ptr != nil)
		buf := (cast([^]u8)(ptr))[:size]
		arena := mem.Arena{}
		mem.arena_init(&arena, buf)
		context.allocator = mem.arena_allocator(&arena)
	}

}
