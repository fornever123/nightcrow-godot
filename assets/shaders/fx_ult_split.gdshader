shader_type canvas_item;
render_mode unshaded;
// 大招「绝影」冷峻版的终结横断：整个画面沿刃口错开——刃口一侧往刃线反方向、往外推，另一侧反过来，中间露一条黑缝。
// 所有量都是屏幕像素。shift = 0 时原样输出。
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform vec2 screen_size = vec2(1280.0, 720.0);
uniform vec2 p0 = vec2(0.0, 360.0);     // 刃口上一点
uniform vec2 dir = vec2(1.0, 0.0);      // 刃口方向（单位向量）
uniform float shift = 0.0;              // 错开量
uniform float gap = 0.0;                // 黑缝宽

float opening(float along) {
	float profile=pow(clamp(1.0-abs(along)/(screen_size.x*0.58),0.0,1.0),1.6);
	return gap*0.5*profile;
}

float fissure(vec2 p,vec2 a,vec2 b,float r0,float r1) {
	vec2 ab=b-a;
	float t=clamp(dot(p-a,ab)/max(dot(ab,ab),0.001),0.0,1.0);
	return length(p-a-ab*t)-mix(r0,r1,t);
}

float forked_crack(vec2 p,vec2 a,vec2 delta) {
	vec2 b=a+delta*vec2(0.28,0.38);
	vec2 c=a+delta*vec2(0.80,0.50);
	return min(fissure(p,a,b,4.0,2.8),min(fissure(p,b,c,2.8,1.4),fissure(p,c,a+delta,1.4,0.0)));
}

void fragment() {
	vec2 px = SCREEN_UV * screen_size;
	vec2 n = vec2(-dir.y, dir.x);
	float d = dot(px - p0, n);
	// Position-only edge detail stays still throughout the impact freeze.
	float along = dot(px-p0,dir);
	float tear = sin(along*0.071)*1.7+sin(along*0.173+1.4)*0.8;
	float cut_dist = abs(d-tear*min(shift/12.0,1.0));
	float aperture = opening(along);
	vec3 col;
	if (cut_dist < aperture) {
		float inner_edge = smoothstep(aperture*0.3,max(aperture,0.001),cut_dist);
		float vein=exp(-abs(d-sin(along*0.016)*aperture*0.22)*0.32)*0.08;
		col=vec3(0.045,0.009,0.08)*inner_edge+vec3(0.38,0.08,0.7)*vein;
	} else {
		float s = d < 0.0 ? 1.0 : -1.0;          // 刃口“上”侧 s = 1
		vec2 off = (dir * 1.0 - n * 0.15) * shift * s;     // 上半往刃线方向、下半反方向（以横向为主）
		vec2 src = (px - off) / screen_size;
		col = texture(screen_tex, clamp(src, vec2(0.0), vec2(1.0))).rgb;
		float edge_dist=cut_dist-aperture;
		float edge = (1.0-smoothstep(0.4,2.0,edge_dist))*min(shift/12.0,1.0);
		float glow=exp(-max(edge_dist,0.0)*0.18)*min(shift/18.0,1.0)*0.28;
		col+=vec3(0.32,0.10,0.65)*glow;
		col = mix(col,vec3(0.93,0.86,1.0),edge*0.95);
	}
	// Four tapered forks break the beam silhouette into fractured space. No TIME,
	// random noise or moving particles: the whole fracture holds still during freeze.
	float growth=min(shift/35.0,1.0);
	vec2 q=vec2(along,d);
	vec2 a=vec2(-160.0,-opening(-160.0));
	float crack=forked_crack(q,a,vec2(-65.0,-90.0)*growth);
	a=vec2(200.0,opening(200.0));
	crack=min(crack,forked_crack(q,a,vec2(84.0,82.0)*growth));
	a=vec2(-340.0,opening(-340.0));
	crack=min(crack,forked_crack(q,a,vec2(-48.0,48.0)*growth));
	a=vec2(355.0,-opening(355.0));
	crack=min(crack,forked_crack(q,a,vec2(58.0,-65.0)*growth));
	float on=min(shift/18.0,1.0);
	col=mix(col,vec3(0.009,0.002,0.02),(1.0-smoothstep(-0.4,0.5,crack))*on);
	float branch_edge=(1.0-smoothstep(0.3,1.1,abs(crack)))*on;
	col=mix(col,vec3(0.83,0.66,1.0),branch_edge*0.85);
	COLOR=vec4(col,1.0);
}
