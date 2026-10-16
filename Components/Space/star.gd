class_name Star
extends Resource
## One star of a [SystemTemplate]: how far away it is, which is how big it looks, and what color it is. Both can be
## left to chance within limits, so one template makes systems that are alike but not the same.
##
## A star is only ever a point in the sky: it cannot be flown to, and it is there to look at and to light the
## system. [StarGenerator] turns each of these into a [StarSpec] (the star as numbers) when a system is made.
##
## [b]Size and temperature.[/b] A template says how hot its systems are with a range, and every system picks a spot
## in that range. Its stars follow: the hotter end pulls them closer by [member distance_variation], the colder
## end pushes them away by as much, so a system's sky always agrees with how warm it is.

## How far this star is.
## 0 makes the star appear massive and takes up a large portion of the sky.
## 1 makes the star far away.
## About 0.42 is a sun-like star at a comfortable distance.
@export_range(0, 1, 0.01) var distance := 0.42
## How far, either way, the system's temperature can move [member distance] (0 never moves it). The hottest
## system of a template has this star closer by this much, and the coldest has it as much farther.
@export_range(0, 1, 0.01) var distance_variation := 0.05
## The color of the star
@export var color: Color = Color.NAVAJO_WHITE
## How much the color changes from one system to the next, from 0 (always exactly [member color]) to 1 (a quite
## different one). A little is enough: stars are never meant to be very strongly colored.
@export_range(0, 1, 0.01) var color_variation := 0.15
## Ignores [member color] and gives the star a natural one instead, from a deep orange to a pale blue (mostly
## close to a sun's yellow-white), chosen differently for every system.
@export var random_color := false
