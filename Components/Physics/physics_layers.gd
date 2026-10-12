class_name PhysicsLayers
extends RefCounted
## The game's 3D physics layers, and what each kind of object collides with.
##
## The layer names also live in Project Settings > Layer Names > 3D Physics, so the
## inspector shows them. Keep the two in step: layer N here is bit N - 1.
##
## A layer is what an object IS; a mask is what it SCANS for. Collision is checked from
## the scanner's side, which is what makes one-way rules possible:
## [codeblock]
## Characters scan Vehicle Interiors, so they stand on them and are blocked by them.
## Vehicle Interiors scan nothing, so a character can never push or move them.
##
## Items scan Characters, so a character walking into one shoves it out of the way.
## Characters do not scan Items, so an item can never block or push a character.
## [/codeblock]
##
## That shove is hard: a character cannot be moved, so one walking an item into a wall squeezes the item
## into it, and through it. Give an item a [SoftCollision3D] instead and it stops scanning
## Characters, and moves itself out of their way, which a wall can stop.
##
##   Layer              What lives there                        It scans
##   1 World            static scenery, terrain, stations       nothing
##   2 Players          player characters                       World, Vehicles, Vehicle Interiors, Creatures
##   3 Creatures        NPCs and animals                        World, Vehicles, Vehicle Interiors, Players, Creatures
##   4 Vehicles         solid vehicles: cars, turrets            World, Vehicles, Vehicle Interiors, Hulls, Players, Creatures, Items
##   5 Vehicle Interiors  floors, walls and furniture inside    nothing (they move with the vehicle)
##   6 Items            loose items lying around                everything solid, characters and other items
##   7 Interactables    InteractableObject3D areas              nothing (only the interaction ray looks at them)
##   8 Projectiles      bullets, missiles                       everything solid, characters and items
##   9 Gravity Fields   gravity areas                           see the gravity masks below
##   10 Hulls           the body of a ship with a walkable inside  World, Vehicles, Hulls (never characters or items)
##
## Players do not scan Players, so they walk through each other (no body blocking, and
## no fighting over prediction). Add PLAYERS to [constant PLAYER_MASK] if you want them solid.
##
## Sensors and triggers that only need to notice bodies (an AI's sight, an enter-zone)
## need no layer of their own: give them layer 0 and set their mask to what they watch.

const WORLD := 1 << 0
const PLAYERS := 1 << 1
const CREATURES := 1 << 2
const VEHICLES := 1 << 3
const VEHICLE_INTERIORS := 1 << 4
const ITEMS := 1 << 5
const INTERACTABLES := 1 << 6
const PROJECTILES := 1 << 7
const GRAVITY_FIELDS := 1 << 8
## The physics body of a vehicle you can walk inside. Characters and items never scan it, so it
## does not fill the inside; they stand on and bump into the walls on Vehicle Interiors instead.
const HULLS := 1 << 9

## Players and creatures together.
const CHARACTERS := PLAYERS | CREATURES
## Everything that stops a character: scenery, hulls and the insides of vehicles.
const SOLID := WORLD | VEHICLES | VEHICLE_INTERIORS

# --- Masks: what each kind of object scans for ---------------------------------------

## Static scenery scans nothing; everything else decides for itself whether to touch it.
const WORLD_MASK := 0
const PLAYER_MASK := SOLID | CREATURES
const CREATURE_MASK := SOLID | CHARACTERS
## A vehicle's outside. A car also scans Vehicle Interiors, so it can drive about inside a ship; the
## ship carries it (see VehicleInterior3D).
const VEHICLE_MASK := WORLD | VEHICLES | VEHICLE_INTERIORS | HULLS | CHARACTERS | ITEMS
## A hull is only for the outside world: scenery, other vehicles and other hulls. Characters and
## items are left out on purpose, or a ship would be solid right through its cargo bay.
const HULL_MASK := WORLD | VEHICLES | HULLS
## Interiors are carried by their vehicle and are never moved by what stands in them.
const VEHICLE_INTERIOR_MASK := 0
## Items bump into the world, each other and anything that walks into them.
const ITEM_MASK := SOLID | CHARACTERS | ITEMS
const INTERACTABLE_MASK := 0
const PROJECTILE_MASK := SOLID | HULLS | CHARACTERS | ITEMS

## Gravity from a planet, a station or space itself pulls everything that can fall.
const WORLD_GRAVITY_MASK := CHARACTERS | VEHICLES | HULLS | ITEMS
## Gravity inside a vehicle holds the people, things and cars in it, but not the ship itself (its body is on Hulls).
const INTERIOR_GRAVITY_MASK := CHARACTERS | ITEMS | VEHICLES

## What the interaction ray can hit. The solid things are there to block it, so a button
## behind a wall cannot be pressed. Characters and items do not block it.
const INTERACTION_RAY_MASK := SOLID | INTERACTABLES
## What stops a door swinging open: scenery, hulls, people and loose items.
const DOOR_BLOCKER_MASK := WORLD | VEHICLES | CHARACTERS | ITEMS
