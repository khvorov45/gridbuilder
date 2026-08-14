package build

import "core:os"
import "core:sys/windows"
import "vendor:directx/d3d_compiler"

Byte :: 1
Kilobyte :: Byte * 1024
Megabyte :: Kilobyte * 1024
Gigabyte :: Megabyte * 1024

main :: proc() {
	make_dir_err := os.make_directory("code/assets_windows")
	assert(make_dir_err == nil || make_dir_err == .Exist)

	// NOTE: shaders
	{
		hlsl, read_entire_file_error := os.read_entire_file("code/shader.hlsl", context.allocator)
		assert(read_entire_file_error == nil)

		vertex_shader_bytecode := compile_shader(hlsl, "vs", "vs_5_0")
		write_file_err := os.write_entire_file(
			"code/assets_windows/vertex_shader_bytecode.bin",
			vertex_shader_bytecode,
		)
		assert(write_file_err == nil)

		pixel_shader_bytecode := compile_shader(hlsl, "ps", "ps_5_0")
		write_file_err = os.write_entire_file("code/assets_windows/pixel_shader_bytecode.bin", pixel_shader_bytecode)
		assert(write_file_err == nil)
	}

	// NOTE: main exe
	{
		process, process_start_error := os.process_start(
			os.Process_Desc {
				command = {
					"odin",
					"build",
					"code",
					"-default-to-nil-allocator",
					"-no-crt",
					"-debug",
					"-strict-style",
					"-vet",
					"-linker:radlink",
					"-subsystem:windows",
					"-microarch:native",
					"-out:build/game_windows.exe",
				},
				stderr = os.stderr,
				stdout = os.stdout,
			},
		)
		assert(process_start_error == nil)

		process_state, process_wait_error := os.process_wait(process)
		assert(process_wait_error == nil)
		assert(process_state.exited)
		assert(process_state.exit_code == 0)
	}
}

compile_shader :: proc(hlsl: []u8, entry_point: cstring, target: cstring) -> []u8 {
	flags := d3d_compiler.D3DCOMPILE {
		.PACK_MATRIX_COLUMN_MAJOR,
		.ENABLE_STRICTNESS,
		.WARNINGS_ARE_ERRORS,
		.DEBUG,
		.SKIP_OPTIMIZATION,
	}

	error: ^d3d_compiler.ID3DBlob
	blob: ^d3d_compiler.ID3DBlob
	compile_result := d3d_compiler.Compile(
		raw_data(hlsl),
		len(hlsl),
		nil,
		nil,
		nil,
		entry_point,
		target,
		transmute(u32)flags,
		0,
		&blob,
		&error,
	)

	if (windows.FAILED(compile_result)) {
		message := cstring(error->GetBufferPointer())
		windows.OutputDebugStringA(message)
	}
	assert(windows.SUCCEEDED(compile_result))

	ptr := blob->GetBufferPointer()
	size := blob->GetBufferSize()

	bytecode := (cast([^]u8)ptr)[:size]
	return bytecode
}
