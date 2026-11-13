// Scrap Heist's engine: the framework's host with the game's two style
// plugins, registered in this order (the coat, then the shading over it).
fn main() {
	modelkit_app::run(vec![sh_paint::plugin(), sh_shading::plugin()]);
}
