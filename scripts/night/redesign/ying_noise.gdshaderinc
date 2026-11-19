// 影街共用噪声（值噪声 + fbm）
float yn_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float yn_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(yn_hash(i), yn_hash(i + vec2(1.0, 0.0)), u.x),
			mix(yn_hash(i + vec2(0.0, 1.0)), yn_hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float yn_fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * yn_noise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return v;
}
