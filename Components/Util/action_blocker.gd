## A utility class for managing permission through blockers.
## Tracks active reasons why something should NOT occur.
## Permission is granted only when no blockers are registered in the [ActionBlocker].
## 
## Example: Multiple systems (low stamina, in dialogue, stunned) can each
## register a blocker preventing an action. The action is only allowed
## when all blockers have been removed.
class_name ActionBlocker
extends RefCounted

## The container that holds all the blockers mapping their id's to the reason they exist.
var _predicates: Dictionary[int, String] = {}

## Adds a blocker
func add(id: int, reason: String) -> void:
	_predicates[id] = reason

## Removes a blocker
func remove(id: int) -> void:
	_predicates.erase(id)

## Returns if the action is permitted
func is_permitted() -> bool:
	return _predicates.is_empty()

## Returns reasons why the action is not permitted
func get_reasons() -> Array[String]:
	return _predicates.values()
