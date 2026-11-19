shader_type spatial;
// 背景线 11-18 立体感试验 · 路线 B「投影浮雕」：站立层原画按深度图挤成浮雕网格，原画当颜色、法线图当法线，交给 3D 灯 / 阴影 / 雾 / 景深。
render_mode cull_disabled, depth_draw_opaque;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D depth_tex : filter_linear;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform vec4 uv_rect = vec4(0.0, 0.0, 1.0, 1.0);   // 只用原图里裁切的那一段
uniform float relief = 300.0;                       // 深度 0 的地方往后退多少世界单位
uniform float base_gain = 1.0;
uniform float tear = 0.3;        // 拉伸面：插值深度和该像素真实深度差太多 → 丢掉，让后面的垫底卡露出来
uniform bool flat_card = false;  // 垫底卡：不挤出，整张放在 back_z

varying float v_d;

void vertex() {
	vec2 uv = uv_rect.xy + UV * uv_rect.zw;
	float d = texture(depth_tex, uv).r;
	v_d = d;
	if (!flat_card) {
		VERTEX.z += (d - 1.0) * relief;
	}
}

void fragment() {
	vec2 uv = uv_rect.xy + UV * uv_rect.zw;
	if (!flat_card && abs(texture(depth_tex, uv).r - v_d) > tear) {
		discard;
	}
	vec4 c = texture(albedo_tex, uv);
	ALBEDO = c.rgb * base_gain;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	NORMAL_MAP = texture(normal_tex, uv).rgb;
	ROUGHNESS = 0.55;
	SPECULAR = 0.35;
}
