package main

Game_State :: struct {
	angle_turns: f32,
}

game_init :: proc(state: ^Game_State) {
	state.angle_turns = 0
}

game_update_and_render :: proc(state: ^Game_State, delta_time_ms: f32) {
	// NOTE: Rotating triangle
	{
		full_rotation_ms: f32 = 200_000
		proportion_for_this_frame := delta_time_ms / full_rotation_ms
		state.angle_turns += proportion_for_this_frame
		if (state.angle_turns > 1) {
			state.angle_turns -= 1
		}
	}
}
