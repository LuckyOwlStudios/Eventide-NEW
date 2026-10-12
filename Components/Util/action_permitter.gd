class_name ActionPermitter
extends RefCounted

## The container that holds all the permitters mapping their id's to the reason they exist.
var _predicates: Dictionary[int, String] = {}

## Adds a blocker
func add(id: int, reason: String) -> void:
	_predicates[id] = reason

## Removes a blocker
func remove(id: int) -> void:
	_predicates.erase(id)

## Returns if the action is permitted
func is_permitted() -> bool:
	return not _predicates.is_empty()

## Returns reasons why the action is not permitted
func get_reasons() -> Array[String]:
	return _predicates.values()
