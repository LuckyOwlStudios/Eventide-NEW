class_name SteamProfile
extends RefCounted
## What the menus need to show another Steam user: their name, their picture, and a way to
## open their Steam page. Every call is safe when Steam did not start; names and pictures
## then come back empty.

const PROFILE_URL := "https://steamcommunity.com/profiles/%d"

## When valid, [method open_profile] calls this with the Steam ID instead of opening
## anything. This exists so a test can click a player without launching a browser.
static var open_override := Callable()

static var _avatars: Dictionary[int, Texture2D] = {}


## The user's Steam name, or an empty string while Steam has not told us yet.
## Steam sends other users' names a moment after they join a lobby; listen for
## [signal SteamLobby.profile_changed] and ask again.
static func display_name(steam_id: int) -> String:
	if not SteamNetwork.is_active or steam_id <= 0:
		return ""
	if steam_id == SteamNetwork.steam_id:
		return SteamNetwork.persona_name
	return Steam.getFriendPersonaName(steam_id)


## The user's 64x64 Steam picture, or null while Steam is still fetching it (it is asked
## to fetch it) or when the user has none. Pictures are kept after the first success.
static func avatar(steam_id: int) -> Texture2D:
	if not SteamNetwork.is_active or steam_id <= 0:
		return null
	if _avatars.has(steam_id):
		return _avatars[steam_id]
	var handle: int = Steam.getMediumFriendAvatar(steam_id)
	if handle <= 0:
		# 0 means no picture, -1 means Steam is still loading it. Either way, ask again.
		Steam.requestUserInformation(steam_id, false)
		return null
	var size: Dictionary = Steam.getImageSize(handle)
	var width := int(size.get("width", 0))
	var height := int(size.get("height", 0))
	if width <= 0 or height <= 0:
		return null
	var pixels: Dictionary = Steam.getImageRGBA(handle)
	var buffer: PackedByteArray = pixels.get("buffer", PackedByteArray())
	if not pixels.get("success", false) or buffer.size() != width * height * 4:
		return null
	var texture := ImageTexture.create_from_image(
		Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, buffer)
	)
	_avatars[steam_id] = texture
	return texture


## Opens the user's Steam page: in the Steam overlay when it is running, otherwise in the
## default web browser.
static func open_profile(steam_id: int) -> void:
	if steam_id <= 0:
		return
	if open_override.is_valid():
		open_override.call(steam_id)
	elif SteamNetwork.is_active and Steam.isOverlayEnabled():
		Steam.activateGameOverlayToUser("steamid", steam_id)
	else:
		OS.shell_open(profile_url(steam_id))


## The web address of the user's Steam page.
static func profile_url(steam_id: int) -> String:
	return PROFILE_URL % steam_id
