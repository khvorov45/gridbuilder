package main

import "core:mem"
import "core:sys/windows"
import "vendor:directx/d3d11"
import "vendor:directx/dxgi"

Vertex :: struct {
	position: [2]f32,
	uv:       [2]f32,
	color:    [3]f32,
}

main :: proc() {
	defer windows.ExitProcess(0)

	// NOTE: Allocate + init
	game_state: ^Game_State
	{
		size := 3 * Gigabyte
		ptr := windows.VirtualAlloc(nil, uint(size), windows.MEM_COMMIT | windows.MEM_RESERVE, windows.PAGE_READWRITE)
		assert(ptr != nil)
		buf := (cast([^]u8)(ptr))[:size]
		game_state = game_init(buf)
	}
	context.allocator = mem.arena_allocator(&game_state.memory.perm)
	context.temp_allocator = mem.arena_allocator(&game_state.memory.frame)
	context.logger = game_state.debug.logger

	// NOTE: Create window
	window: struct {
		hwnd: windows.HWND,
		prev: windows.WINDOWPLACEMENT,
		dim:  [2]int,
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
		device:           ^d3d11.IDevice,
		context_:         ^d3d11.IDeviceContext,
		swapchain:        ^dxgi.ISwapChain1,
		vbuffer:          ^d3d11.IBuffer,
		layout:           ^d3d11.IInputLayout,
		vshader:          ^d3d11.IVertexShader,
		pshader:          ^d3d11.IPixelShader,
		ubuffer:          ^d3d11.IBuffer,
		texture_view:     ^d3d11.IShaderResourceView,
		sampler:          ^d3d11.ISamplerState,
		blend_state:      ^d3d11.IBlendState,
		rasterizer_state: ^d3d11.IRasterizerState,
		depth_state:      ^d3d11.IDepthStencilState,
		rt_view:          ^d3d11.IRenderTargetView,
		ds_view:          ^d3d11.IDepthStencilView,
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

			vertex_shader_bytecode := #load("assets_windows/vertex_shader_bytecode.bin")
			d3d11_data.device->CreateVertexShader(
				raw_data(vertex_shader_bytecode),
				len(vertex_shader_bytecode),
				nil,
				&d3d11_data.vshader,
			)

			pixel_shader_bytecode := #load("assets_windows/pixel_shader_bytecode.bin")
			d3d11_data.device->CreatePixelShader(
				raw_data(pixel_shader_bytecode),
				len(pixel_shader_bytecode),
				nil,
				&d3d11_data.pshader,
			)

			d3d11_data.device->CreateInputLayout(
				raw_data(&desc),
				len(desc),
				raw_data(vertex_shader_bytecode),
				len(vertex_shader_bytecode),
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

		// NOTE: Blend
		{
			desc := d3d11.BLEND_DESC {
				RenderTarget = {
					0 = {
						BlendEnable = windows.TRUE,
						SrcBlend = .SRC_ALPHA,
						DestBlend = .INV_SRC_ALPHA,
						BlendOp = .ADD,
						SrcBlendAlpha = .SRC_ALPHA,
						DestBlendAlpha = .INV_SRC_ALPHA,
						BlendOpAlpha = .ADD,
						RenderTargetWriteMask = u8(d3d11.COLOR_WRITE_ENABLE_ALL),
					},
				},
			}
			d3d11_data.device->CreateBlendState(&desc, &d3d11_data.blend_state)
		}

		// NOTE: Rasteriser
		{
			desc := d3d11.RASTERIZER_DESC {
				FillMode        = .SOLID,
				CullMode        = .NONE,
				DepthClipEnable = windows.TRUE,
			}
			d3d11_data.device->CreateRasterizerState(&desc, &d3d11_data.rasterizer_state)
		}

		// NOTE: Depth and stencil
		{
			desc := d3d11.DEPTH_STENCIL_DESC {
				DepthEnable      = windows.FALSE,
				DepthWriteMask   = .ALL,
				DepthFunc        = .LESS,
				StencilEnable    = windows.FALSE,
				StencilReadMask  = d3d11.DEFAULT_STENCIL_READ_MASK,
				StencilWriteMask = d3d11.DEFAULT_STENCIL_WRITE_MASK,
			}
			d3d11_data.device->CreateDepthStencilState(&desc, &d3d11_data.depth_state)
		}
	}

	// NOTE: Debug font
	debug_font: struct {
		tex: []u8,
	}

	{
		debug_font.tex = #load("assets_windows/debug_font_tex.bin")
		dim_slice := #load("assets_windows/debug_font_glyph_dim.bin", []f32)
		assert(len(dim_slice) == 2)

		game_state.debug.font.glyph_dim = {dim_slice[0], dim_slice[1]}
	}

	// NOTE: Timer
	clock: struct {
		freq:    windows.LARGE_INTEGER,
		counter: windows.LARGE_INTEGER,
	}

	{
		{
			result := windows.QueryPerformanceFrequency(&clock.freq)
			assert(bool(result))
		}

		{
			result := windows.QueryPerformanceCounter(&clock.counter)
			assert(bool(result))
		}
	}

	// NOTE: mainloop
	free_all(context.temp_allocator)
	for {
		defer free_all(context.temp_allocator)

		for msg: windows.MSG; windows.PeekMessageW(&msg, nil, 0, 0, windows.PM_REMOVE); {
			if msg.message == windows.WM_QUIT {
				return
			}
			windows.TranslateMessage(&msg)
			windows.DispatchMessageW(&msg)
		}

		// NOTE: Resize/init if necessary
		{

			// NOTE: New dim
			rect: windows.RECT
			{
				result := windows.GetClientRect(window.hwnd, &rect)
				assert(bool(result))
			}
			width := rect.right - rect.left
			height := rect.bottom - rect.top

			if (d3d11_data.rt_view == nil || int(width) != window.dim.x || int(height) != window.dim.y) {

				// NOTE: Release all
				if (d3d11_data.rt_view != nil) {
					d3d11_data.context_->ClearState()
					d3d11_data.rt_view->Release()
					d3d11_data.ds_view->Release()
					d3d11_data.rt_view = nil
				}

				if (width > 0 && height > 0) {

					// NOTE: swapchain
					{
						result := d3d11_data.swapchain->ResizeBuffers(0, u32(width), u32(height), .UNKNOWN, {})
						assert(windows.SUCCEEDED(result))
					}

					// NOTE: Render target view
					{
						backbuffer: ^d3d11.ITexture2D
						defer backbuffer->Release()

						d3d11_data.swapchain->GetBuffer(0, d3d11.ITexture2D_UUID, cast(^rawptr)&backbuffer)
						d3d11_data.device->CreateRenderTargetView(
							cast(^d3d11.IResource)backbuffer,
							nil,
							&d3d11_data.rt_view,
						)
					}

					// NOTE: Depth stencil view
					{
						desc := d3d11.TEXTURE2D_DESC {
							Width      = u32(width),
							Height     = u32(height),
							MipLevels  = 1,
							ArraySize  = 1,
							Format     = .D32_FLOAT,
							SampleDesc = {1, 0},
							Usage      = .DEFAULT,
							BindFlags  = {.DEPTH_STENCIL},
						}

						depth: ^d3d11.ITexture2D
						defer depth->Release()

						d3d11_data.device->CreateTexture2D(&desc, nil, &depth)
						d3d11_data.device->CreateDepthStencilView(depth, nil, &d3d11_data.ds_view)
					}

					window.dim = {int(width), int(height)}
				}
			}
		}

		if (d3d11_data.rt_view != nil) {

			delta_time_ms: f32
			{
				new_counter: windows.LARGE_INTEGER
				defer clock.counter = new_counter

				{
					result := windows.QueryPerformanceCounter(&new_counter)
					assert(bool(result))
				}

				diff := new_counter - clock.counter
				assert(diff > 0)

				delta_time_ms = f32(f64(diff) / f64(clock.freq) * 1000)
			}

			// NOTE: Game
			game_update_and_render(game_state, delta_time_ms)

			// NOTE: Clear
			{
				color := [4]f32{0.392, 0.584, 0.929, 1}
				d3d11_data.context_->ClearRenderTargetView(d3d11_data.rt_view, &color)
				d3d11_data.context_->ClearDepthStencilView(d3d11_data.ds_view, {.DEPTH, .STENCIL}, 1, 0)
			}

			// NOTE: Uniform update
			{
				height_over_width := f32(window.dim.y) / f32(window.dim.x)
				sin_angle := sin(0)
				cos_angle := cos(0)
							// odinfmt: disable
				rot_matrix := matrix[4,4]f32{
					cos_angle * height_over_width, -sin_angle, 0, 0,
					sin_angle * height_over_width, cos_angle, 0, 0,
					0, 0, 0, 0,
					0, 0, 0, 1,
				}
				// odinfmt: enable

				mapped: d3d11.MAPPED_SUBRESOURCE
				d3d11_data.context_->Map(d3d11_data.ubuffer, 0, .WRITE_DISCARD, {}, &mapped)
				mem.copy(mapped.pData, &rot_matrix, size_of(rot_matrix))
				d3d11_data.context_->Unmap(d3d11_data.ubuffer, 0)
			}

			// NOTE: Input assembler
			{
				d3d11_data.context_->IASetInputLayout(d3d11_data.layout)
				d3d11_data.context_->IASetPrimitiveTopology(.TRIANGLELIST)
				stride := u32(size_of(Vertex))
				offset: u32 = 0
				d3d11_data.context_->IASetVertexBuffers(0, 1, &d3d11_data.vbuffer, &stride, &offset)
			}

			// NOTE: Vertex Shader
			{
				d3d11_data.context_->VSSetConstantBuffers(0, 1, &d3d11_data.ubuffer)
				d3d11_data.context_->VSSetShader(d3d11_data.vshader, nil, 0)
			}

			// NOTE: Rasterizer stage
			{
				viewport := d3d11.VIEWPORT {
					TopLeftX = 0,
					TopLeftY = 0,
					Width    = f32(window.dim.x),
					Height   = f32(window.dim.y),
					MinDepth = 0,
					MaxDepth = 1,
				}
				d3d11_data.context_->RSSetViewports(1, &viewport)
				d3d11_data.context_->RSSetState(d3d11_data.rasterizer_state)
			}

			// NOTE: Pixel shader
			{
				d3d11_data.context_->PSSetSamplers(0, 1, &d3d11_data.sampler)
				d3d11_data.context_->PSSetShaderResources(0, 1, &d3d11_data.texture_view)
				d3d11_data.context_->PSSetShader(d3d11_data.pshader, nil, 0)
			}

			// NOTE: Output merger
			{
				d3d11_data.context_->OMSetBlendState(d3d11_data.blend_state, nil, ~u32(0))
				d3d11_data.context_->OMSetDepthStencilState(d3d11_data.depth_state, 0)
				d3d11_data.context_->OMSetRenderTargets(1, &d3d11_data.rt_view, d3d11_data.ds_view)
			}

			// NOTE: Draw
			{
				d3d11_data.context_->Draw(3, 0)
			}
		}

		// NOTE: Present
		{
			vsync := true
			result := d3d11_data.swapchain->Present(vsync ? 1 : 0, {})
			if (result == dxgi.STATUS_OCCLUDED) {
				if (vsync) {
					windows.Sleep(10)
				}
			} else if (windows.FAILED(result)) {
				return
			}
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
