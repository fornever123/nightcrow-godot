// [YG-MARK] 字成城（11-08）：雨丝和悬停水珠。靠近亮着的灯被染成琥珀，靠近斩线被照白。
// INSTANCE_CUSTOM：r 亮度，g 类型（0 雨丝 / 1 水珠），b 水珠的偏移相位
shader_type canvas_item;
render_mode blend_add, unshaded;

uniform vec2 uCut0 = vec2(1000.0, 372.0);
uniform vec2 uN = vec2(.2419, .9703);
uniform float uLight = 0.0;
uniform vec4 uLampX = vec4(380.0, 720.0, 1060.0, 1400.0);
uniform vec4 uLamp = vec4(0.0);

varying vec2 vUV;
varying float vA;
varying float vKind;
varying vec3 vTint;

void vertex() {
	vUV = UV;
	vA = INSTANCE_CUSTOM.r;
	vKind = INSTANCE_CUSTOM.g;
	vec2 w = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	vec3 tint = vec3(.54, .63, .80);
	for (int i = 0; i < 4; i++) {
		float r = length((w - vec2(uLampX[i], 700.0)) * vec2(1.0, .7));
		tint += exp(-r / 110.0) * vec3(1.5, .86, .36) * uLamp[i];
	}
	float sd = abs(dot(w - uCut0, uN));
	tint += exp(-sd / 80.0) * vec3(.7, .66, .56) * uLight;
	vTint = tint;
}

void fragment() {
	float a;
	if (vKind < .5) {
		// 雨丝：头亮尾淡，横向很窄
		float x = abs(vUV.x - .5) * 2.0;
		float tail = pow(vUV.y, 1.8);
		a = exp(-x * x * 5.0) * tail;
	} else {
		// 水珠：边缘一圈折光，左上一个高光，中间透明
		vec2 q = (vUV - .5) * 2.0;
		q.y *= .86;
		float r = length(q);
		float body = smoothstep(1.0, .78, r);
		a = body * .34 + smoothstep(.72, .95, r) * body * .12;
		a += exp(-dot(q - vec2(-.30, -.36), q - vec2(-.30, -.36)) * 18.0) * 2.0;
		a += exp(-dot(q - vec2(.10, .46), q - vec2(.10, .46)) * 10.0) * .7;
	}
	COLOR = vec4(vTint * a * vA, 1.0);
}
