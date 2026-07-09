@echo off
odin build code -default-to-panic-allocator -no-crt -debug -strict-style -vet -linker:radlink -subsystem:windows -microarch:native -out:build/game_windows.exe