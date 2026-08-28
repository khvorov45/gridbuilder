package main

import "core:log"
import "core:mem"

Byte :: 1
Kilobyte :: 1024 * Byte
Megabyte :: 1024 * Kilobyte
Gigabyte :: 1024 * Megabyte

ASCII_Char_Count :: 128

Log_Entry :: struct {
	str: string,
	buf: [Kilobyte]u8,
}

Log_Circle_Buf :: struct {
	entries: [128]Log_Entry,
	head:    int, // NOTE: Next entry will be written to this index
}

logger_proc :: proc(data: rawptr, level: log.Level, text: string, options: log.Options, location := #caller_location) {
	log_circle_buf := cast(^Log_Circle_Buf)(data)
	assert(log_circle_buf.head >= 0 && log_circle_buf.head < len(log_circle_buf.entries))

	entry := &log_circle_buf.entries[log_circle_buf.head]
	bytes_to_copy := min(len(text), len(entry.buf))
	mem.copy(&entry.buf, raw_data(text), bytes_to_copy)

	entry.str = cast(string)entry.buf[:bytes_to_copy]

	new_head := log_circle_buf.head + 1
	if new_head >= len(log_circle_buf.entries) {
		new_head = 0
	}
	log_circle_buf.head = new_head
}

// NOTE: Assumed to be textured by one atlas and be drawn 1-to-1
Rect_Px_Space_Textured :: struct {
	topleft_px_space: [2]f32,
	topleft_in_atlas: [2]f32,
	dim:              [2]f32,
}

Game_State :: struct {
	memory: struct {
		perm:  mem.Arena,
		frame: mem.Arena,
	},
	debug:  struct {
		log_circle_buf: Log_Circle_Buf,
		logger:         log.Logger,
		// NOTE: Assume monospace font that has a glyph for all ASCII characters
		// Assume all glyphs are packed in the same atlas
		// Do not assume how they are packed in the atlas
		font:           struct {
			glyph_dim:              [2]f32,
			glyph_topleft_in_atlas: [ASCII_Char_Count][2]f32,
		},
	},
	render: struct {
		rects_px_space_textured: [dynamic; 1024 * 1024]Rect_Px_Space_Textured,
	},
}

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

	log.debug("update by", delta_time_ms, "ms")

	clear(&game_state.render.rects_px_space_textured)
	{
		topleft := [2]f32{0, 0}
		for log_entry in game_state.debug.log_circle_buf.entries {
			if len(log_entry.str) > 0 {
				render_string(game_state, log_entry.str, topleft)
				topleft.y += game_state.debug.font.glyph_dim.y
			}
		}
	}
}

render_string :: proc(game_state: ^Game_State, text: string, topleft_init: [2]f32) {
	topleft := topleft_init
	for ch in text {
		glyph_topleft_in_atlas := game_state.debug.font.glyph_topleft_in_atlas[ch]
		render_rect_screen_textured(game_state, topleft, glyph_topleft_in_atlas, game_state.debug.font.glyph_dim)
		topleft.x += game_state.debug.font.glyph_dim.x
	}
}

render_rect_screen_textured :: proc(
	game_state: ^Game_State,
	rect_topleft_px_space: [2]f32,
	tex_topleft_in_atlas: [2]f32,
	dim: [2]f32,
) {
	if (len(game_state.render.rects_px_space_textured) < cap(game_state.render.rects_px_space_textured)) {
		append(
			&game_state.render.rects_px_space_textured,
			Rect_Px_Space_Textured{rect_topleft_px_space, tex_topleft_in_atlas, dim},
		)
	}
}
