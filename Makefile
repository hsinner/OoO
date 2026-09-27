.PHONY: lint test check clean
VERILATOR ?= verilator
lint:
	$(VERILATOR) --lint-only -Wall --top-module ooo_core -f rtl/files.f
test:
	mkdir -p build/obj
	$(VERILATOR) --cc --exe --build -Wall --top-module ooo_core -f rtl/files.f $(CURDIR)/tests/core_test.cpp --Mdir build/obj -CFLAGS "-std=c++17" -o core_test
	./build/obj/core_test
check: lint test
clean:
	$(RM) -r build/obj
