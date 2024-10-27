ifeq ($(OS),Windows_NT)
	uname_S := Windows
else
	uname_S := $(shell uname -s)
endif

run:
	zig build run -freference-trace

test:
	zig build test -freference-trace

test:
	rm -rf .zig-cache zig-out

valgrind:
	zig build
	./scripts/valgrind.sh

install-deps:
ifeq ($(uname_S), Darwin)
	brew install rocksdb
endif
ifeq ($(uname_S), Linux)
	sudo apt install -y librocksdb-dev valgrind
endif
