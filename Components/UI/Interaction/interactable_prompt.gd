class_name InteractablePrompt
extends Node3D
## The selector frame and the options panel of one interactable, as two billboard quads. It hangs
## off the interactable like its dot does, so wherever the interactable goes (a ship at full speed,
## say) the prompt goes with it, drawn the same smooth way, and nobody has to place it.
##
## The interactable makes one the first time it is looked at. The player's InteractableObjectPrompter
## decides what it shows: it gives the options texture, sizes the two quads and shows or hides it.

## The frame drawn around the interactable.
@onready var selector: MeshInstance3D = %Selector
## The panel of options, drawn from the prompter's SubViewport.
@onready var options: MeshInstance3D = %Options


func set_options_texture(texture: Texture2D) -> void:
	var material := options.mesh.material as StandardMaterial3D
	if material.albedo_texture != texture:
		material.albedo_texture = texture
