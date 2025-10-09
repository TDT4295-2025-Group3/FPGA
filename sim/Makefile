# ================================
# Makefile for Verilator VGA Simulator
# ================================

VERILATOR       = verilator
VERILATOR_FLAGS = --trace -cc --exe \
	-Wall -O3 -D_REENTRANT \
	-Wno-UNUSED -Wno-UNDRIVEN -Wno-WIDTH -Wno-STMTDLY \
	-Wno-PINCONNECTEMPTY  \
	-I/usr/include/SDL2 -D_REENTRANT -Wno-IMPORTSTAR 

FILELIST   = ../filelist.f
SOURCELIST := $(shell cat $(FILELIST))
SRC      := $(addprefix ../, $(SOURCELIST)) stubs/BUFG.sv stubs/MMCME2_BASE.sv stubs/div_rasterizer.sv main.cpp top_sim.sv

TOP_MODULE = top_sim
BUILD_DIR  = obj_dir
TARGET     = vga_sim

.PHONY: all clean show-src

all: $(TARGET)

show-src:
	@echo "SystemVerilog compilation order:"
	@echo $(SRC)

$(TARGET): $(SRC)
	@echo "Compiling SystemVerilog files in order:"
	@echo $(SRC)
	@echo "Running Verilator (generating C++, with --trace)..."
	$(VERILATOR) $(VERILATOR_FLAGS) $(SRC) --top-module $(TOP_MODULE)
	@echo "Building generated objects and final binary..."
	$(MAKE) -C $(BUILD_DIR) -f V$(TOP_MODULE).mk V$(TOP_MODULE) LDLIBS="`sdl2-config --libs`"
	@echo "Copying simulator binary to ./$(TARGET)"
	cp $(BUILD_DIR)/V$(TOP_MODULE) ./$(TARGET)

clean:
	rm -rf $(BUILD_DIR) $(TARGET)
