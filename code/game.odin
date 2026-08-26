package main

import "core:mem"

Byte :: 1
Kilobyte :: 1024 * Byte
Megabyte :: 1024 * Kilobyte
Gigabyte :: 1024 * Megabyte

Circular_Buffer :: struct($T: typeid) {
	entries: []T,
	head:    int,
}

Log_Entry :: struct {
	str: string,
	buf: [Kilobyte]u8,
}

Game_State :: struct {
	memory: struct {
		perm:  mem.Arena,
		frame: mem.Arena,
	},
	debug:  struct {
		log: Circular_Buffer(Log_Entry),
	},
}

test :: proc() {}

game_init :: proc(buf: []u8) -> ^Game_State {
	assert(len(buf) >= 3 * Gigabyte)

	// NOTE: Memory + game state
	game_state: ^Game_State
	{
		mem_perm: mem.Arena
		mem_frame: mem.Arena

		buf_perm := buf[:1 * Gigabyte]
		buf_temp := buf[len(buf_perm):len(buf)]

		mem.arena_init(&mem_perm, buf_perm)
		mem.arena_init(&mem_frame, buf_temp)

		game_state = new(Game_State, mem.arena_allocator(&mem_perm))
		game_state.memory.perm = mem_perm
		game_state.memory.frame = mem_frame
	}

	context.allocator = mem.arena_allocator(&game_state.memory.perm)
	context.temp_allocator = mem.arena_allocator(&game_state.memory.frame)
	defer free_all(context.temp_allocator)


	// NOTE: Debug
	{
		game_state.debug.log.entries = make([]Log_Entry, 128)
	}

	return game_state
}

game_update_and_render :: proc(state: ^Game_State, delta_time_ms: f32) {
	context.allocator = mem.arena_allocator(&state.memory.perm)
	context.temp_allocator = mem.arena_allocator(&state.memory.frame)
	defer free_all(context.temp_allocator)
}
