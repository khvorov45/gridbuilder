package build

import "core:bufio"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:sys/windows"
import "vendor:directx/d3d_compiler"

Byte :: 1
Kilobyte :: Byte * 1024
Megabyte :: Kilobyte * 1024
Gigabyte :: Megabyte * 1024

Asset_List_Entry :: struct {
	name: string,
	data: []u8,
}

global_asset_list: [dynamic]Asset_List_Entry

main :: proc() {

	// NOTE: shaders
	{
		hlsl, read_entire_file_error := os.read_entire_file("code/shader.hlsl", context.allocator)
		assert(read_entire_file_error == nil)

		vertex_shader := compile_shader(hlsl, "vs", "vs_5_0")
		append_asset(vertex_shader)

		pixel_shader := compile_shader(hlsl, "ps", "ps_5_0")
		append_asset(pixel_shader)
	}

	// NOTE: generated code
	{
		code_builder := strings.builder_make()
		wr := strings.to_writer(&code_builder)

		fmt.wprintln(wr, "package main")
		fmt.wprintln(wr, "")

		// NOTE: Assets header struct definition
		fmt.wprintln(wr, "Assets_Header :: struct {")
		for entry in global_asset_list {
			fmt.wprintln(wr, "\t", entry.name, "_len: uintptr,", sep = "")
		}
		fmt.wprintln(wr, "}")

		code_str := strings.to_string(code_builder)
		write_entire_file_error := os.write_entire_file("code/generated_windows.odin", code_str)
		assert(write_entire_file_error == nil)
	}

	// NOTE: asset file
	{
		file, open_error := os.open("code/assets_windows.bin", {.Write, .Create})
		assert(open_error == nil)
		defer {
			flush_error := os.flush(file)
			assert(flush_error == nil)

			close_error := os.close(file)
			assert(close_error == nil)
		}
		file_writer := os.to_writer(file)

		buffer := make([]u8, 1 * Gigabyte)
		wr: bufio.Writer
		bufio.writer_init_with_buf(&wr, file_writer, buffer)
		defer {
			flush_error := bufio.writer_flush(&wr)
			assert(flush_error == nil)
		}

		write :: proc(wr: ^bufio.Writer, ptr: rawptr, len: int) {
			bufio.writer_write(wr, (cast([^]u8)ptr)[:len])
		}

		// NOTE: header
		for entry in global_asset_list {
			length := len(entry.data)
			write(&wr, &length, size_of(length))
		}

		// NOTE: data
		for entry in global_asset_list {
			bufio.writer_write(&wr, entry.data)
		}
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

append_asset :: proc(data: []u8, expr := #caller_expression(data)) {
	append(&global_asset_list, Asset_List_Entry{name = expr, data = data})
}
