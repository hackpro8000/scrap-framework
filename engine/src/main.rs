// This game's engine: the framework's host and the plugins it is built from,
// registered in the order listed. A plugin crate goes in art/plugins/<name>,
// joins Cargo.toml (here and the workspace members) and is listed below, as
//   modelkit_app::run(vec![my_style::plugin()]);
fn main() {
	modelkit_app::run(vec![]);
}
