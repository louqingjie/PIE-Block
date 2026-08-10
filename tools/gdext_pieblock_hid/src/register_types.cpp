#include "register_types.h"

#include "hid_win.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

using namespace godot;

void initialize_pieblock_hid_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(PieBlockHidWindows);
	Engine::get_singleton()->register_singleton("PieBlockHidWindows", memnew(PieBlockHidWindows));
}

void uninitialize_pieblock_hid_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	Engine::get_singleton()->unregister_singleton("PieBlockHidWindows");
	memdelete(PieBlockHidWindows::get_singleton());
}

extern "C" {
// Initialization.
GDExtensionBool GDE_EXPORT pieblock_hid_library_init(GDExtensionInterfaceGetProcAddress p_get_proc_address, GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	godot::GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);

	init_obj.register_initializer(initialize_pieblock_hid_module);
	init_obj.register_terminator(uninitialize_pieblock_hid_module);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);

	return init_obj.init();
}
}
