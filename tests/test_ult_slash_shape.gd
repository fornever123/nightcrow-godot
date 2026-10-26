extends SceneTree
var checks := 0
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		print("FAIL: ",message)
func _initialize() -> void:
	var path := "res://scripts/presentation/ult_slash_shape.gd"
	check(ResourceLoader.exists(path),"Sculpted slash geometry is available")
	if not ResourceLoader.exists(path):
		print("ULT_SLASH_SHAPE_TESTS: %d checks / %d failures" % [checks,failures.size()])
		quit(1)
		return
	var shape = load(path)
	var a := Vector2(10,30)
	var b := Vector2(1010,30)
	var full: PackedVector2Array = shape.ribbon(a,b,16,28)
	check(full.size()>=50,"Blade silhouette has enough segments for a smooth contour")
	check(full[0].is_equal_approx(a) and full[full.size()/2-1].is_equal_approx(b),"Both blade ends taper to the trajectory endpoints")
	check(absf(_area(full))>100,"Blade has a nonzero filled silhouette")
	var finite := true
	for p in full: finite = finite and p.is_finite()
	check(finite,"All blade vertices are finite")
	var partial: PackedVector2Array = shape.ribbon(a,b,16,28,0.65,0.2)
	check(partial[0].x>=a.x+199 and partial[partial.size()/2-1].x<=a.x+651,"Head and tail follow the direction of the swing")
	check(partial[0].distance_to(partial[partial.size()-1])<0.01,"Dissolving tail has a closed tapered tip")
	check(shape.ribbon(a,a,16,28).is_empty(),"Zero-length swing produces no degenerate polygon")
	check(shape.ribbon(a,b,0,28).is_empty(),"Zero-width slash produces no geometry")
	check(shape.ribbon(a,b,16,28,0.2,0.7).is_empty(),"Expired head/tail range produces no geometry")
	var reverse: PackedVector2Array = shape.ribbon(b,a,16,28)
	check(absf(_area(full)-_area(reverse))<0.1,"Reversed slash retains its blade area")
	var straight: PackedVector2Array = shape.ribbon(a,b,16,0)
	check(absf(straight[8].y-full[8].y)>5.0,"Changing bend changes the blade shape, not just its color")
	for ratio in [0.25,0.5,1.0]:
		var scaled: PackedVector2Array=shape.ribbon(a*ratio,b*ratio,16*ratio,28*ratio)
		check(absf(_area(scaled)-_area(full)*ratio*ratio)<0.1,"Blade scales consistently at %.2f" % ratio)
	var has_arc := false
	for method in shape.get_script_method_list():
		if method.name=="arc": has_arc=true
	check(has_arc,"Spatial crescent geometry is available")
	if has_arc:
		var center:=Vector2(640,460)
		var radii:=Vector2(400,160)
		var crescent: PackedVector2Array=shape.arc(center,radii,2.8,3.5,24.0,-0.2)
		check(crescent.size()>=80,"Spatial crescent has smooth tessellation")
		check(absf(_area(crescent))>8000,"Crescent has a substantial blade silhouette")
		check(crescent[0].distance_to(crescent[crescent.size()-1])<0.01,"Crescent tail closes to a point")
		var mirrored: PackedVector2Array=shape.arc(center,radii,6.3,-3.5,24.0,-0.2)
		check(absf(absf(_area(crescent))-absf(_area(mirrored)))<0.1,"Reverse sweep preserves the blade silhouette area")
		check(shape.arc(center,Vector2.ZERO,0,PI,20,0).is_empty(),"Zero-radius arc is rejected")
		check(shape.arc(center,radii,0,0,20,0).is_empty(),"Zero-angle arc is rejected")
		check(shape.arc(center,radii,0,PI,20,0,0.2,0.8).is_empty(),"Finished arc head-tail range is rejected")
		var short_arc: PackedVector2Array=shape.arc(center,radii,2.8,3.5,24.0,-0.2,0.7,0.3)
		check(absf(_area(short_arc))<absf(_area(crescent)),"Moving head and eroding tail reduce visible blade area")
	print("ULT_SLASH_SHAPE_TESTS: %d checks / %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
func _area(poly: PackedVector2Array) -> float:
	var area:=0.0
	for i in poly.size(): area+=poly[i].cross(poly[(i+1)%poly.size()])
	return area*0.5
