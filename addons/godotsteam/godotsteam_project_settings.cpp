/***************************************************************************/
/*  godotsteam_project_settings.cpp                                        */
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

#include "godotsteam_project_settings.h"

#define APP_TYPE_SETTING "steam/initialization/app_data/app_type"
#define APP_ID_SETTING "steam/initialization/app_data/app_id"
#define DEMO_ID_SETTING "steam/initialization/app_data/demo_id"
#define PLAYTEST_ID_SETTING "steam/initialization/app_data/playtest_id"
#define TOOL_ID_SETTING "steam/initialization/app_data/tool_id"
#define STARTUP_INIT_SETTING "steam/initialization/processes/initialize_on_startup"
#define EMBED_CALLBACKS_SETTING "steam/initialization/processes/embed_callbacks"
#define MAX_CHANNELS_SETTING "steam/multiplayer_peer/max_channels"

#define OLD_APP_ID_SETTING "steam/initialization/app_id"
#define OLD_STARTUP_INIT_SETTING "steam/initialization/initialize_on_startup"
#define OLD_EMBED_CALLBACKS_SETTING "steam/initialization/embed_callbacks"

#ifndef GLOBAL_GET
#define GLOBAL_GET(m_prop) ProjectSettings::get_singleton()->get_setting_with_override(m_prop)
#endif


void SteamProjectSettings::register_settings() {
	// Set up our app types and their IDs
	if (!ProjectSettings::get_singleton()->has_setting(APP_TYPE_SETTING)) {
		ProjectSettings::get_singleton()->set(APP_TYPE_SETTING, 0);
	}
#ifdef GDEXTENSION
	Dictionary property_info;
	property_info["name"] = APP_TYPE_SETTING;
	property_info["type"] = Variant::INT;
	property_info["hint"] = PROPERTY_HINT_ENUM;
	property_info["hint_string"] = "App / Game, Demo, Playtest, Tool";
	ProjectSettings::get_singleton()->add_property_info(property_info);
#else
	PropertyInfo property_info(Variant::INT, APP_TYPE_SETTING, PROPERTY_HINT_ENUM, "App / Game, Demo, Playtest, Tool");
	ProjectSettings::get_singleton()->set_custom_property_info(property_info);
#endif
	ProjectSettings::get_singleton()->set_initial_value(APP_TYPE_SETTING, 0);
	ProjectSettings::get_singleton()->set_as_basic(APP_TYPE_SETTING, true);

	if (!ProjectSettings::get_singleton()->has_setting(APP_ID_SETTING)) {
		ProjectSettings::get_singleton()->set(APP_ID_SETTING, 0);
	}
	ProjectSettings::get_singleton()->set_initial_value(APP_ID_SETTING, 0);
	ProjectSettings::get_singleton()->set_as_basic(APP_ID_SETTING, true);

	if (!ProjectSettings::get_singleton()->has_setting(DEMO_ID_SETTING)) {
		ProjectSettings::get_singleton()->set(DEMO_ID_SETTING, 0);
	}
	ProjectSettings::get_singleton()->set_initial_value(DEMO_ID_SETTING, 0);
	ProjectSettings::get_singleton()->set_as_basic(DEMO_ID_SETTING, true);

	if (!ProjectSettings::get_singleton()->has_setting(PLAYTEST_ID_SETTING)) {
		ProjectSettings::get_singleton()->set(PLAYTEST_ID_SETTING, 0);
	}
	ProjectSettings::get_singleton()->set_initial_value(PLAYTEST_ID_SETTING, 0);
	ProjectSettings::get_singleton()->set_as_basic(PLAYTEST_ID_SETTING, true);

	if (!ProjectSettings::get_singleton()->has_setting(TOOL_ID_SETTING)) {
		ProjectSettings::get_singleton()->set(TOOL_ID_SETTING, 0);
	}
	ProjectSettings::get_singleton()->set_initial_value(TOOL_ID_SETTING, 0);
	ProjectSettings::get_singleton()->set_as_basic(TOOL_ID_SETTING, true);

	// Set up our initialization process options
	if (!ProjectSettings::get_singleton()->has_setting(STARTUP_INIT_SETTING)) {
		ProjectSettings::get_singleton()->set(STARTUP_INIT_SETTING, false);
	}
	ProjectSettings::get_singleton()->set_initial_value(STARTUP_INIT_SETTING, false);
	ProjectSettings::get_singleton()->set_as_basic(STARTUP_INIT_SETTING, true);

	if (!ProjectSettings::get_singleton()->has_setting(EMBED_CALLBACKS_SETTING)) {
		ProjectSettings::get_singleton()->set(EMBED_CALLBACKS_SETTING, false);
	}
	ProjectSettings::get_singleton()->set_initial_value(EMBED_CALLBACKS_SETTING, false);
	ProjectSettings::get_singleton()->set_as_basic(EMBED_CALLBACKS_SETTING, true);

	// Set up our MultiplayerPeer stuff
	if (!ProjectSettings::get_singleton()->has_setting(MAX_CHANNELS_SETTING)) {
		ProjectSettings::get_singleton()->set(MAX_CHANNELS_SETTING, 4);
	}
	ProjectSettings::get_singleton()->set_initial_value(MAX_CHANNELS_SETTING, 4);
	ProjectSettings::get_singleton()->set_as_basic(MAX_CHANNELS_SETTING, true);
	// Port in any pre-GodotSteam v4.20 settings
	if (ProjectSettings::get_singleton()->has_setting(OLD_APP_ID_SETTING)) {
		WARN_PRINT_ONCE("Found older app ID project setting, converting it");
		ProjectSettings::get_singleton()->set_setting(APP_ID_SETTING, ProjectSettings::get_singleton()->get_setting(OLD_APP_ID_SETTING));
		ProjectSettings::get_singleton()->clear(OLD_APP_ID_SETTING);
	}
	if (ProjectSettings::get_singleton()->has_setting(OLD_STARTUP_INIT_SETTING)) {
		WARN_PRINT_ONCE("Found older initialize on startup setting, converting it");
		ProjectSettings::get_singleton()->set_setting(STARTUP_INIT_SETTING, ProjectSettings::get_singleton()->get_setting(OLD_STARTUP_INIT_SETTING));
		ProjectSettings::get_singleton()->clear(OLD_STARTUP_INIT_SETTING);
	}
	if (ProjectSettings::get_singleton()->has_setting(OLD_EMBED_CALLBACKS_SETTING)) {
		WARN_PRINT_ONCE("Found older embed callbacks setting, converting it");
		ProjectSettings::get_singleton()->set_setting(EMBED_CALLBACKS_SETTING, ProjectSettings::get_singleton()->get_setting(OLD_EMBED_CALLBACKS_SETTING));
		ProjectSettings::get_singleton()->clear(OLD_EMBED_CALLBACKS_SETTING);
	}
}

int SteamProjectSettings::get_app_id() {
	return GLOBAL_GET(APP_ID_SETTING);
}

int SteamProjectSettings::get_app_type() {
	return GLOBAL_GET(APP_TYPE_SETTING);
}

bool SteamProjectSettings::get_auto_init() {
	return GLOBAL_GET(STARTUP_INIT_SETTING);
}

int SteamProjectSettings::get_demo_id() {
	return GLOBAL_GET(DEMO_ID_SETTING);
}

bool SteamProjectSettings::get_embed_callbacks() {
	return GLOBAL_GET(EMBED_CALLBACKS_SETTING);
}

int SteamProjectSettings::get_id_in_use() {
	if (get_app_type() == 1) {
		return get_demo_id();
	} else if (get_app_type() == 2) {
		return get_playtest_id();
	} else if (get_app_type() == 3) {
		return get_tool_id();
	} else {
		return get_app_id();
	}
}

int SteamProjectSettings::get_max_channels() {
	return GLOBAL_GET(MAX_CHANNELS_SETTING);
}

int SteamProjectSettings::get_playtest_id() {
	return GLOBAL_GET(PLAYTEST_ID_SETTING);
}

int SteamProjectSettings::get_tool_id() {
	return GLOBAL_GET(TOOL_ID_SETTING);
}
