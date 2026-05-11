.PHONY: all trace rust cpp_proto build run check clean

all: trace rust cpp_proto build run check

trace:
	python3 python_module/gen_trace_proto.py

rust:
	cd rust_runtime && cargo run

cpp_proto:
	protoc -I proto --cpp_out=sim_cpp/cpp_pb proto/packet.proto

BUILD_DIR := /tmp/fpga_exchange_build
LOCAL_BIN := sim_cpp/build/Vstage_transform

build:
	rm -rf "$(BUILD_DIR)"
	mkdir -p "$(BUILD_DIR)/rtl"
	mkdir -p "$(BUILD_DIR)/sim_cpp/cpp_pb"
	mkdir -p sim_cpp/build
	mkdir -p sim_cpp/build/waves

	cp "rtl/stage_transform.sv" "$(BUILD_DIR)/rtl/"
	cp "sim_cpp/main.cpp" "$(BUILD_DIR)/sim_cpp/"
	cp "sim_cpp/cpp_pb/packet.pb.cc" "$(BUILD_DIR)/sim_cpp/cpp_pb/"
	cp "sim_cpp/cpp_pb/packet.pb.h" "$(BUILD_DIR)/sim_cpp/cpp_pb/"

	cd "$(BUILD_DIR)" && \
	verilator --cc rtl/stage_transform.sv \
	  --exe sim_cpp/main.cpp sim_cpp/cpp_pb/packet.pb.cc \
	  --build \
	  --trace \
	  --Mdir obj_dir \
	  -CFLAGS "-I sim_cpp" \
	  -LDFLAGS "-lprotobuf"

	cp -r "$(BUILD_DIR)/obj_dir" sim_cpp/build/	
	cp "$(BUILD_DIR)/obj_dir/Vstage_transform" "$(LOCAL_BIN)"

run:
	./$(LOCAL_BIN)

check:
	python3 python_module/check_results.py

clean:
	rm -rf "$(BUILD_DIR)" \
		sim_cpp/build \
		rust_runtime/target \
		results/*.csv \
		binary_traces/*.pb
