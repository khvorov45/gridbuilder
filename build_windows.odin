package build

import "core:os"
import "core:strings"
import "core:sys/windows"
import "vendor:directx/d3d_compiler"

Byte :: 1
Kilobyte :: Byte * 1024
Megabyte :: Kilobyte * 1024
Gigabyte :: Megabyte * 1024

main :: proc() {
	create_empty_dir("build")
	create_empty_dir("code/assets_windows")

	// NOTE: shaders
	{
		hlsl, read_entire_file_error := os.read_entire_file("code/shader.hlsl", context.allocator)
		assert(read_entire_file_error == nil)

		vertex_shader_bytecode := compile_shader(hlsl, "vs", "vs_5_0")
		write_asset_bin(vertex_shader_bytecode)

		pixel_shader_bytecode := compile_shader(hlsl, "ps", "ps_5_0")
		write_asset_bin(pixel_shader_bytecode)
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

write_asset_bin :: proc(data: []u8, name := #caller_expression(data)) {
	path, cat_err := strings.concatenate({"code/assets_windows/", name, ".bin"})
	assert(cat_err == nil)
	write_file_err := os.write_entire_file(path, data)
	assert(write_file_err == nil)
}

create_empty_dir :: proc(path: string) {
	if os.exists(path) {
		assert(os.is_dir(path))

		handle, open_err := os.open(path)
		assert(open_err == nil)

		it := os.read_directory_iterator_create(handle)
		defer os.read_directory_iterator_destroy(&it)

		for info in os.read_directory_iterator(&it) {
			remove_err := os.remove(info.fullpath)
			assert(remove_err == nil)
		}
	} else {
		make_err := os.make_directory(path)
		assert(make_err == nil)
	}
}
