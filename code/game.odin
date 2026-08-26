package main

import "core:log"
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
		log_circle_buf: Circular_Buffer(Log_Entry),
		logger:         log.Logger,
	},
}

logger_proc :: proc(
	data: rawptr,
	level: log.Level,
	text: string,
	options: log.Options,
	location := #caller_location,
) {}

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
		game_state.debug.log_circle_buf.entries = make([]Log_Entry, 128)
		game_state.debug.logger = log.Logger {
			procedure    = logger_proc,
			data         = &game_state.debug.log_circle_buf,
			lowest_level = .Debug,
			options      = log.Options {
				.Level,
				.Date,
				.Time,
				.Short_File_Path,
				.Long_File_Path,
				.Line,
				.Procedure,
				.Terminal_Color,
				.Thread_Id,
			},
		}
	}

	return game_state
}

game_update_and_render :: proc(game_state: ^Game_State, delta_time_ms: f32) {
	frame_temp_memory := mem.begin_arena_temp_memory(&game_state.memory.frame)
	defer mem.end_arena_temp_memory(frame_temp_memory)

	log.debug("test1")
	log.debug("test2")
	log.debug("test3")
	log.debug("test4")
}
