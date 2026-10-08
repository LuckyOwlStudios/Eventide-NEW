/***************************************************************************/
/*  register_types.cpp                                                     */
/***************************************************************************/
/*                         This file is part of:                           */
/*                              GODOTSTEAM                                 */
/*                         https://godotsteam.com                          */
/***************************************************************************/
/* Copyright (c) 2015-Current | GP Garcia, Chris Ridenour,                 */
/*                              and Contributors                           */
/*                                                                         */
/* View all contributors at https://godotsteam.com/contribute/contributors */
/*                                                                         */
/* Permission is hereby granted, free of charge, to any person obtaining   */
/* a copy of this software and associated documentation files (the         */
/* "Software"), to deal in the Software without restriction, including     */
/* without limitation the rights to use, copy, modify, merge, publish,     */
/* distribute, sublicense, and/or sell copies of the Software, and to      */
/* permit persons to whom the Software is furnished to do so, subject to   */
/* the following conditions:                                               */
/*                                                                         */
/* The above copyright notice and this permission notice shall be included */
/* in all copies or substantial portions of the Software.                  */
/*                                                                         */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,         */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF      */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY    */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,    */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE       */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                  */
/***************************************************************************/

#include "register_types.h"

#ifdef GDEXTENSION
#include "godotsteam.h"
#include "godotsteam_multiplayer_peer.h"
#include "godotsteam_project_settings.h"

#include <gdextension_interface.h>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

using namespace godot;
#else
#include "godotsteam.h"
#include "godotsteam_multiplayer_peer.h"
#include "godotsteam_project_settings.h"

#include "core/config/engine.h"
#include "core/object/class_db.h"
#endif

static Steam *SteamPtr = nullptr;


void initialize_godotsteam_module(ModuleInitializationLevel level) {
	if (level == MODULE_INITIALIZATION_LEVEL_CORE) {
		ClassDB::register_class<Steam>();
		SteamPtr = memnew(Steam);
#ifdef GDEXTENSION
		Engine::get_singleton()->register_singleton("Steam", Steam::get_singleton());
#else
		Engine::get_singleton()->add_singleton(Engine::Singleton("Steam", Steam::get_singleton()));
#endif
		// Setup Project Settings
		SteamProjectSettings::register_settings();
		if (Engine::get_singleton()->is_editor_hint()) {
			return;
		}
		if (!SteamProjectSettings::get_auto_init()) {
			return;
		}
		Steam::get_singleton()->run_internal_initialization();
	}
	if (level == MODULE_INITIALIZATION_LEVEL_SCENE) {
		ClassDB::register_class<SteamPacketPeer>();
		ClassDB::register_class<SteamMultiplayerPeer>();

		if (SteamProjectSettings::get_auto_init() && SteamProjectSettings::get_embed_callbacks()) {
			WARN_PRINT_ONCE("[STEAM] Cannot use auto-initialization and embed callbacks together currently. Embed callbacks ignored; call run_callbacks() manually.");
			// This just warns until we can fix the inability to link to SceneTree this early.
			// Steam::get_singleton()->set_internal_callbacks();
		}
	}
}


void uninitialize_godotsteam_module(ModuleInitializationLevel level) {
	if (level == MODULE_INITIALIZATION_LEVEL_CORE) {
#ifdef GDEXTENSION
		Engine::get_singleton()->unregister_singleton("Steam");
#else
		Engine::get_singleton()->remove_singleton("Steam");
#endif
		memdelete(SteamPtr);
	}
}


#ifdef GDEXTENSION
extern "C" {
GDExtensionBool GDE_EXPORT godotsteam_init(GDExtensionInterfaceGetProcAddress p_interface, const GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	godot::GDExtensionBinding::InitObject init_obj(p_interface, p_library, r_initialization);
	init_obj.register_initializer(initialize_godotsteam_module);
	init_obj.register_terminator(uninitialize_godotsteam_module);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_CORE);
	return init_obj.init();
}
}
#endif
