## Inspector-configurable action offered by an InteractableObject3D.
## Use an Input Map action instead of a physical key so prompts and controls
## continue to work when the player changes their key bindings.
class_name InteractionOption
extends Resource

enum TriggerType {
	PRESS,
	DOUBLE_PRESS,
	HOLD,
}

@export_category("Identity")
## Stable name scripts can use when array indices may be reordered later.
@export var option_id: StringName = &"interact"

@export_category("Input and Prompt")
## Input Map action that activates this option, such as interact, primary_fire,
## or flashlight_toggle. The prompt displays its first assigned input event.
@export var input_action: StringName = &"interact"

## Message displayed after the input hint. For example, "To Pickup" becomes
## "[E] To Pickup" when the interact action is bound to E.
@export var prompt := "Interact"

## Determines whether the action fires on one press, two quick presses, or after
## the input has been held for Hold Duration Seconds.
@export var trigger_type := TriggerType.PRESS

@export_category("Timing")
## Required hold duration when Trigger Type is Hold.
@export_range(0.1, 10.0, 0.05, "or_greater", "suffix:s") var hold_duration_seconds := 1.0

## Maximum delay between presses when Trigger Type is Double Press.
@export_range(0.1, 1.0, 0.05, "or_greater", "suffix:s") var double_press_window_seconds := 0.3

## Minimum delay after this option succeeds before it may be used again.
@export_range(0.0, 60.0, 0.05, "or_greater", "suffix:s") var cooldown_seconds := 0.0

@export_category("Availability")
## Allows this option to be hidden and disabled without removing it from the list.
@export var enabled := true

## Permanently disables only this option after its first successful use.
@export var one_shot := false
