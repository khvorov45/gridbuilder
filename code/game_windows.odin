package main

import "core:mem"
import "core:os"
import "core:sys/windows"
import "vendor:directx/d3d11"
import "vendor:directx/d3d_compiler"
import "vendor:directx/dxgi"

Byte :: 1
Kilobyte :: 1024 * Byte
Megabyte :: 1024 * Kilobyte
Gigabyte :: 1024 * Megabyte

main :: proc() {
	defer windows.ExitProcess(0)

	// NOTE: Allocate
	memory: struct {
		perm, temp: mem.Arena,
	}
	{
		size := 3 * Gigabyte
		ptr := windows.VirtualAlloc(nil, uint(size), windows.MEM_COMMIT | windows.MEM_RESERVE, windows.PAGE_READWRITE)
		assert(ptr != nil)
		buf := (cast([^]u8)(ptr))[:size]

		buf_perm := buf[:1 * Gigabyte]
		buf_temp := buf[len(buf_perm):size]

		mem.arena_init(&memory.perm, buf_perm)
		mem.arena_init(&memory.temp, buf_temp)
	}
	context.allocator = mem.arena_allocator(&memory.perm)
	context.temp_allocator = mem.arena_allocator(&memory.temp)

	// NOTE: Create window
	window: struct {
		hwnd: windows.HWND,
		prev: windows.WINDOWPLACEMENT,
	} = {
		prev = {length = size_of(windows.WINDOWPLACEMENT)},
	}

	{
		window_class := windows.WNDCLASSEXW {
			cbSize        = size_of(windows.WNDCLASSEXW),
			lpfnWndProc   = window_proc,
			hInstance     = windows.HANDLE(windows.GetModuleHandleW(nil)),
			hIcon         = windows.LoadIconA(nil, windows.IDI_APPLICATION),
			hCursor       = windows.LoadCursorA(nil, windows.IDC_ARROW),
			lpszClassName = cstring16("gridbuilder_window_class"),
		}

		{
			atom := windows.RegisterClassExW(&window_class)
			assert(atom != 0)
		}

		window.hwnd = windows.CreateWindowExW(
			windows.WS_EX_APPWINDOW,
			window_class.lpszClassName,
			cstring16("gridbuilder"),
			windows.WS_OVERLAPPEDWINDOW,
			windows.CW_USEDEFAULT,
			windows.CW_USEDEFAULT,
			windows.CW_USEDEFAULT,
			windows.CW_USEDEFAULT,
			nil,
			nil,
			window_class.hInstance,
			nil,
		)
		assert(window.hwnd != nil)

		// NOTE: The window will not show up yet but this will prevent a white flash at least on windows 11
		toggle_fullscreen(window.hwnd, &window.prev)

		// NOTE: Does not fail apparently
		// If the window was previously visible, the return value is nonzero.
		// If the window was previously hidden, the return value is zero.
		windows.ShowWindow(window.hwnd, windows.SW_SHOWDEFAULT)
	}

	// NOTE: Set up D3D11
	d3d11_data: struct {
		device:       ^d3d11.IDevice,
		context_:     ^d3d11.IDeviceContext,
		swapchain:    ^dxgi.ISwapChain1,
		vbuffer:      ^d3d11.IBuffer,
		layout:       ^d3d11.IInputLayout,
		vshader:      ^d3d11.IVertexShader,
		pshader:      ^d3d11.IPixelShader,
		ubuffer:      ^d3d11.IBuffer,
		texture_view: ^d3d11.IShaderResourceView,
		sampler:      ^d3d11.ISamplerState,
	}

	{

		// NOTE: Device
		levels: []d3d11.FEATURE_LEVEL = {._11_0}
		create_device_result := d3d11.CreateDevice(
			nil,
			.HARDWARE,
			nil,
			{.DEBUG},
			raw_data(levels),
			u32(len(levels)),
			d3d11.SDK_VERSION,
			&d3d11_data.device,
			nil,
			&d3d11_data.context_,
		)
		assert(windows.SUCCEEDED(create_device_result))

		// NOTE: Debug break D3D11
		{
			info: ^d3d11.IInfoQueue
			defer info->Release()

			query_interface_result := d3d11_data.device->QueryInterface(d3d11.IInfoQueue_UUID, cast(^rawptr)&info)
			assert(windows.SUCCEEDED(query_interface_result))

			set_break_on_severity_corruption_result := info->SetBreakOnSeverity(.CORRUPTION, windows.TRUE)
			assert(windows.SUCCEEDED(set_break_on_severity_corruption_result))

			set_break_on_severity_error_result := info->SetBreakOnSeverity(.ERROR, windows.TRUE)
			assert(windows.SUCCEEDED(set_break_on_severity_error_result))
		}

		// NOTE: Debug break DXGI
		{
			info: ^dxgi.IInfoQueue
			defer info->Release()

			get_debug_interface_result := dxgi.GetDebugInterface1(0, dxgi.IInfoQueue_UUID, cast(^rawptr)&info)
			assert(windows.SUCCEEDED(get_debug_interface_result))

			set_break_on_severity_corruption_result := info->SetBreakOnSeverity(
				dxgi.DEBUG_ALL,
				.CORRUPTION,
				windows.TRUE,
			)
			assert(windows.SUCCEEDED(set_break_on_severity_corruption_result))

			set_break_on_severity_error_result := info->SetBreakOnSeverity(dxgi.DEBUG_ALL, .ERROR, windows.TRUE)
			assert(windows.SUCCEEDED(set_break_on_severity_error_result))
		}

		// NOTE: According to Martins:
		// after this there's no need to check for any errors on device functions manually
		// so all HRESULT return  values in this code will be ignored
		// debugger will break on errors anyway

		// NOTE: Swapchain
		{
			dxgi_device: ^dxgi.IDevice
			defer dxgi_device->Release()

			query_interface_result := d3d11_data.device->QueryInterface(dxgi.IDevice_UUID, cast(^rawptr)&dxgi_device)
			assert(windows.SUCCEEDED(query_interface_result))

			dxgi_adapter: ^dxgi.IAdapter
			defer dxgi_adapter->Release()

			get_adapter_result := dxgi_device->GetAdapter(&dxgi_adapter)
			assert(windows.SUCCEEDED(get_adapter_result))

			factory: ^dxgi.IFactory2
			defer factory->Release()

			get_parent_result := dxgi_adapter->GetParent(dxgi.IFactory2_UUID, cast(^rawptr)&factory)
			assert(windows.SUCCEEDED(get_parent_result))

			desc: dxgi.SWAP_CHAIN_DESC1 = {
				Format = .R8G8B8A8_UNORM,
				SampleDesc = {Count = 1, Quality = 0},
				BufferUsage = {.RENDER_TARGET_OUTPUT},
				BufferCount = 2,
				Scaling = .NONE,
				SwapEffect = .FLIP_DISCARD,
			}

			CreateSwapChainForHwnd_result := factory->CreateSwapChainForHwnd(
				d3d11_data.device,
				window.hwnd,
				&desc,
				nil,
				nil,
				&d3d11_data.swapchain,
			)
			assert(windows.SUCCEEDED(CreateSwapChainForHwnd_result))

			// NOTE: According to Martins:
			// disable silly Alt+Enter changing monitor resolution to match window size
			MakeWindowAssociation_result := factory->MakeWindowAssociation(window.hwnd, {.NO_ALT_ENTER})
			assert(windows.SUCCEEDED(MakeWindowAssociation_result))
		}

		// NOTE: Vertex buffer
		Vertex :: struct {
			position: [2]f32,
			uv:       [2]f32,
			color:    [3]f32,
		}

		{
			data := [?]Vertex {
				{{-0.00, +0.75}, {25.0, 50.0}, {1, 0, 0}},
				{{+0.75, -0.50}, {0.0, 0.0}, {0, 1, 0}},
				{{-0.75, -0.50}, {50.0, 0.0}, {0, 0, 1}},
			}

			desc := d3d11.BUFFER_DESC {
				ByteWidth = size_of(data),
				Usage     = .IMMUTABLE,
				BindFlags = {.VERTEX_BUFFER},
			}

			initial := d3d11.SUBRESOURCE_DATA {
				pSysMem = &data,
			}

			d3d11_data.device->CreateBuffer(&desc, &initial, &d3d11_data.vbuffer)
		}

		// NOTE: Shaders + layout
		{
			desc := [?]d3d11.INPUT_ELEMENT_DESC {
				{"POSITION", 0, .R32G32_FLOAT, 0, u32(offset_of(Vertex, position)), .VERTEX_DATA, 0},
				{"TEXCOORD", 0, .R32G32_FLOAT, 0, u32(offset_of(Vertex, uv)), .VERTEX_DATA, 0},
				{"COLOR", 0, .R32G32B32_FLOAT, 0, u32(offset_of(Vertex, color)), .VERTEX_DATA, 0},
			}

			flags := d3d_compiler.D3DCOMPILE {
				.PACK_MATRIX_COLUMN_MAJOR,
				.ENABLE_STRICTNESS,
				.WARNINGS_ARE_ERRORS,
				.DEBUG,
				.SKIP_OPTIMIZATION,
			}

			error: ^d3d_compiler.ID3DBlob

			vblob: ^d3d_compiler.ID3DBlob
			defer vblob->Release()

			pblob: ^d3d_compiler.ID3DBlob
			defer pblob->Release()

			hlsl, err := os.read_entire_file("code/shader.hlsl", context.temp_allocator)
			assert(err == nil)

			defer free_all(context.temp_allocator)

			vs_compile_result := d3d_compiler.Compile(
				raw_data(hlsl),
				len(hlsl),
				nil,
				nil,
				nil,
				"vs",
				"vs_5_0",
				transmute(u32)flags,
				0,
				&vblob,
				&error,
			)
			if (windows.FAILED(vs_compile_result)) {
				message := cstring(error->GetBufferPointer())
				windows.OutputDebugStringA(message)
			}
			assert(windows.SUCCEEDED(vs_compile_result))


			ps_compile_result := d3d_compiler.Compile(
				raw_data(hlsl),
				len(hlsl),
				nil,
				nil,
				nil,
				"ps",
				"ps_5_0",
				transmute(u32)flags,
				0,
				&pblob,
				&error,
			)
			if (windows.FAILED(ps_compile_result)) {
				message := cstring(error->GetBufferPointer())
				windows.OutputDebugStringA(message)
			}
			assert(windows.SUCCEEDED(ps_compile_result))

			d3d11_data.device->CreateVertexShader(
				vblob->GetBufferPointer(),
				vblob->GetBufferSize(),
				nil,
				&d3d11_data.vshader,
			)

			d3d11_data.device->CreatePixelShader(
				pblob->GetBufferPointer(),
				pblob->GetBufferSize(),
				nil,
				&d3d11_data.pshader,
			)

			d3d11_data.device->CreateInputLayout(
				raw_data(&desc),
				len(desc),
				vblob->GetBufferPointer(),
				vblob->GetBufferSize(),
				&d3d11_data.layout,
			)
		}

		// NOTE: ubuffer
		{
			desc := d3d11.BUFFER_DESC {
				ByteWidth      = 4 * 4 * size_of(f32),
				Usage          = .DYNAMIC,
				BindFlags      = {.CONSTANT_BUFFER},
				CPUAccessFlags = {.WRITE},
			}

			d3d11_data.device->CreateBuffer(&desc, nil, &d3d11_data.ubuffer)
		}

		// NOTE: Texture
		{
			pixels := [?]u32{0x80000000, 0xffffffff, 0xffffffff, 0x80000000}
			width := 2
			height := 2

			desc := d3d11.TEXTURE2D_DESC {
				Width      = u32(width),
				Height     = u32(height),
				MipLevels  = 1,
				ArraySize  = 1,
				Format     = .R8G8B8A8_UNORM,
				SampleDesc = {1, 0},
				Usage      = .IMMUTABLE,
				BindFlags  = {.SHADER_RESOURCE},
			}

			data := d3d11.SUBRESOURCE_DATA {
				pSysMem     = &pixels,
				SysMemPitch = u32(width) * size_of(u32),
			}

			texture: ^d3d11.ITexture2D
			defer texture->Release()

			d3d11_data.device->CreateTexture2D(&desc, &data, &texture)
			d3d11_data.device->CreateShaderResourceView(cast(^d3d11.IResource)texture, nil, &d3d11_data.texture_view)
		}

		// NOTE: Sampler
		{
			desc := d3d11.SAMPLER_DESC {
				Filter        = .MIN_MAG_MIP_POINT,
				AddressU      = .WRAP,
				AddressV      = .WRAP,
				AddressW      = .WRAP,
				MipLODBias    = 0,
				MaxAnisotropy = 1,
				MinLOD        = 0,
				MaxLOD        = d3d11.FLOAT32_MAX,
			}

			d3d11_data.device->CreateSamplerState(&desc, &d3d11_data.sampler)
		}
	}

	// NOTE: mainloop
	for {
		for msg: windows.MSG; windows.PeekMessageW(&msg, nil, 0, 0, windows.PM_REMOVE); {
			if msg.message == windows.WM_QUIT {
				return
			}
			windows.TranslateMessage(&msg)
			windows.DispatchMessageW(&msg)
		}
	}
}

window_proc :: proc "system" (
	hwnd: windows.HWND,
	msg: windows.UINT,
	wparam: windows.WPARAM,
	lparam: windows.LPARAM,
) -> (
	result: windows.LRESULT = 0,
) {

	switch msg {
	case windows.WM_DESTROY:
		windows.PostQuitMessage(0)
	case:
		result = windows.DefWindowProcW(hwnd, msg, wparam, lparam)
	}

	return result
}

// https://devblogs.microsoft.com/oldnewthing/20100412-00/?p=14353
toggle_fullscreen :: proc(hwnd: windows.HWND, prev: ^windows.WINDOWPLACEMENT) {
	style := windows.GetWindowLongW(hwnd, windows.GWL_STYLE)
	assert(style != 0)

	is_currently_windowed := u32(style) & windows.WS_OVERLAPPEDWINDOW != 0
	if (is_currently_windowed) {
		// NOTE: Set to fullscreen

		mi := windows.MONITORINFO {
			cbSize = size_of(windows.MONITORINFO),
		}

		store_prev_result := windows.GetWindowPlacement(hwnd, prev)
		assert(bool(store_prev_result))

		monitor := windows.MonitorFromWindow(hwnd, windows.Monitor_From_Flags.MONITOR_DEFAULTTOPRIMARY)
		get_monitor_info_result := windows.GetMonitorInfoW(monitor, &mi)
		assert(bool(get_monitor_info_result))

		if (store_prev_result && get_monitor_info_result) {
			set_window_long_result := windows.SetWindowLongW(
				hwnd,
				windows.GWL_STYLE,
				i32(u32(style) & ~windows.WS_OVERLAPPEDWINDOW),
			)
			assert(set_window_long_result != 0)

			set_window_pos_result := windows.SetWindowPos(
				hwnd,
				windows.HWND_TOP,
				mi.rcMonitor.left,
				mi.rcMonitor.top,
				mi.rcMonitor.right - mi.rcMonitor.left,
				mi.rcMonitor.bottom - mi.rcMonitor.top,
				windows.SWP_NOOWNERZORDER | windows.SWP_FRAMECHANGED,
			)
			assert(bool(set_window_pos_result))
		}
	} else {
		// NOTE: Set to windowed

		set_window_long_result := windows.SetWindowLongW(
			hwnd,
			windows.GWL_STYLE,
			i32(u32(style) | windows.WS_OVERLAPPEDWINDOW),
		)
		assert(set_window_long_result != 0)

		set_window_placement_result := windows.SetWindowPlacement(hwnd, prev)
		assert(bool(set_window_placement_result))

		set_window_pos_result := windows.SetWindowPos(
			hwnd,
			nil,
			0,
			0,
			0,
			0,
			windows.SWP_NOMOVE |
			windows.SWP_NOSIZE |
			windows.SWP_NOZORDER |
			windows.SWP_NOOWNERZORDER |
			windows.SWP_FRAMECHANGED,
		)
		assert(bool(set_window_pos_result))
	}
}
