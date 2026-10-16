class_name InvitePlayerButton
extends Button
## A button that opens the Steam overlay invite dialog for the current lobby,
## allowing the host to invite friends directly from their Steam friends list.

func _pressed() -> void:
	if not SteamNetwork.has_lobby():
		push_warning("Cannot open Steam invites without an active Steam lobby.")
		return
	else:
		Steam.activateGameOverlayInviteDialog(SteamNetwork.lobby_id)
