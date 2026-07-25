package main

import "core:mem"
import "core:sys/windows"
import "vendor:directx/d3d11"

Byte :: 1
Kilobyte :: 1024 * Byte
Megabyte :: 1024 * Kilobyte
Gigabyte :: 1024 * Megabyte

main :: proc() {
	defer windows.ExitProcess(0)

	// NOTE: Allocate
	arena: mem.Arena
	{
		size := 1 * Gigabyte
		ptr := windows.VirtualAlloc(nil, uint(size), windows.MEM_COMMIT | windows.MEM_RESERVE, windows.PAGE_READWRITE)
		assert(ptr != nil)
		buf := (cast([^]u8)(ptr))[:size]
		mem.arena_init(&arena, buf)
		context.allocator = mem.arena_allocator(&arena)
	}

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
		device:   ^d3d11.IDevice,
		context_: ^d3d11.IDeviceContext,
	}

	{

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

		{
			info: ^d3d11.IInfoQueue

			query_interface_result := d3d11_data.device->QueryInterface(d3d11.IInfoQueue_UUID, cast(^rawptr)&info)
			assert(windows.SUCCEEDED(query_interface_result))

			set_break_on_severity_corruption_result := info->SetBreakOnSeverity(.CORRUPTION, windows.TRUE)
			assert(windows.SUCCEEDED(set_break_on_severity_corruption_result))

			set_break_on_severity_error_result := info->SetBreakOnSeverity(.ERROR, windows.TRUE)
			assert(windows.SUCCEEDED(set_break_on_severity_error_result))

			info->Release()
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
