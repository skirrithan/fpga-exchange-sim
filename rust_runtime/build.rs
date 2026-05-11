fn main() {
    prost_build::compile_protos(
        &["../proto/packet.proto"],
        &["../proto"],
    ).unwrap();
}