package main

// https://en.wikipedia.org/wiki/Bhaskara_I%27s_sine_approximation_formula
sin :: proc(turns: f32) -> (result: f32) {
	val01 := turns - f32(i32(turns))
	if (val01 < 0) {
		val01 += 1
	}
	x := val01
	f: f32 = 5.0 / 64.0
	if (val01 < 0.5) {
		r: f32 = x * (0.5 - x)
		result = r / (f - 0.25 * r)
	} else {
		r := (x - 0.5) * (1.0 - x)
		result = -(r / (f - 0.25 * r))
	}
	return result
}

cos :: proc(turns: f32) -> f32 {
	result := sin(turns + 0.25)
	return result
}
