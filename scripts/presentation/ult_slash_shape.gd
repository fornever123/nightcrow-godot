extends RefCounted
## Pure blade geometry in screen pixels; head/tail use chronological path progress.
static func ribbon(a: Vector2, b: Vector2, width: float, bend: float,
		head: float = 1.0, tail: float = 0.0) -> PackedVector2Array:
	head = clampf(head,0.0,1.0)
	tail = clampf(tail,0.0,1.0)
	if width<=0.0 or head-tail<0.001 or a.distance_squared_to(b)<1.0:
		return PackedVector2Array()
	var direction := (b-a).normalized()
	var normal := direction.orthogonal()
	var upper := PackedVector2Array()
	var lower := PackedVector2Array()
	var taper := minf(0.065,(head-tail)*0.25)
	for i in 33:
		var t := lerpf(tail,head,float(i)/32.0)
		var envelope := pow(maxf(sin(PI*t),0.0),0.7)
		var close_tail := clampf((t-tail)/taper,0.0,1.0)
		var close_head := clampf((head-t)/taper,0.0,1.0)
		close_tail = close_tail*close_tail*(3.0-2.0*close_tail)
		close_head = close_head*close_head*(3.0-2.0*close_head)
		var half := width*envelope*(0.62+0.6*t)*close_tail*close_head
		var center := a.lerp(b,t)+normal*bend*sin(PI*t)
		upper.append(center+normal*half)
		lower.append(center-normal*half)
	for i in range(lower.size()-1,-1,-1): upper.append(lower[i])
	return upper


## Elliptical sword plane. Sweep sign controls attack direction, not stroke thickness.
static func arc(center: Vector2, radii: Vector2, start: float, sweep: float,
		width: float, tilt: float, head: float=1.0, tail: float=0.0) -> PackedVector2Array:
	head=clampf(head,0.0,1.0)
	tail=clampf(tail,0.0,1.0)
	if minf(radii.x,radii.y)<1.0 or absf(sweep)<0.001 or width<=0.0 or head-tail<0.001:
		return PackedVector2Array()
	var upper:=PackedVector2Array()
	var lower:=PackedVector2Array()
	var taper:=minf(0.07,(head-tail)*0.25)
	for i in 65:
		var t:=lerpf(tail,head,float(i)/64.0)
		var angle:=start+sweep*t
		var pos:=Vector2(cos(angle)*radii.x,sin(angle)*radii.y).rotated(tilt)+center
		var tangent:=Vector2(-sin(angle)*radii.x,cos(angle)*radii.y).rotated(tilt).normalized()
		var normal:=tangent.orthogonal()*signf(sweep)
		var close_tail:=smoothstep(0.0,1.0,clampf((t-tail)/taper,0.0,1.0))
		var close_head:=smoothstep(0.0,1.0,clampf((head-t)/taper,0.0,1.0))
		var half:=width*pow(maxf(sin(PI*t),0.0),0.65)*close_tail*close_head
		upper.append(pos+normal*half)
		lower.append(pos-normal*half)
	for i in range(lower.size()-1,-1,-1): upper.append(lower[i])
	return upper
