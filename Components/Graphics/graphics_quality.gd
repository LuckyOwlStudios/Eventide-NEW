class_name GraphicsQuality
extends RefCounted
## The player's Graphics Quality setting, as something code can ask about.
##
## The choice itself is the [code]graphics_quality[/code] setting in the Settings menu.
## Ask this class instead of reading the setting, and compare levels instead of names:
## [codeblock]
## if GraphicsQuality.is_at_least(GraphicsQuality.Level.HIGH):
##     enable_the_expensive_thing()
## [/codeblock]
## To react when the player changes it, connect to [signal Settings.setting_changed] and
## look for [constant SETTING_ID].

enum Level { LOW, MEDIUM, HIGH, ULTRA }

const SETTING_ID: StringName = &"graphics_quality"


static func get_level() -> Level:
	return level_from_id(StringName(Settings.get_setting(SETTING_ID, &"medium")))


static func is_at_least(level: Level) -> bool:
	return get_level() >= level


static func level_from_id(id: StringName) -> Level:
	match id:
		&"low": return Level.LOW
		&"high": return Level.HIGH
		&"ultra": return Level.ULTRA
	return Level.MEDIUM
