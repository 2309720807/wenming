shader_type canvas_item;

// 养成主界面背景：深邃星空
// 三段式垂直渐变 + 径向暗角 + 微弱星云光晕

uniform vec4 color_top : source_color = vec4(0.03, 0.05, 0.16, 1.0);
uniform vec4 color_mid : source_color = vec4(0.05, 0.04, 0.18, 1.0);
uniform vec4 color_bottom : source_color = vec4(0.025, 0.025, 0.10, 1.0);

void fragment() {
	float y = UV.y;
	float x = UV.x;

	// 垂直渐变
	vec3 col;
	if (y < 0.4) {
		float t = y / 0.4;
		col = mix(color_top.rgb, color_mid.rgb, t * t);
	} else {
		float t = (y - 0.4) / 0.6;
		col = mix(color_mid.rgb, color_bottom.rgb, t);
	}

	// 水平微弱变化：偏蓝
	float x_bias = x * 0.015;
	col += vec3(x_bias * 0.05, x_bias * 0.1, x_bias * 0.35);

	// 径向暗角
	vec2 center = vec2(0.5, 0.45);
	float dist = distance(UV, center);
	float vignette = smoothstep(0.35, 1.2, dist);
	col *= mix(1.0, 0.5, vignette);

	// 微弱星云光晕：中心偏上区域略亮
	float nebula = exp(-pow(dist * 2.5, 2.0)) * 0.04;
	col += vec3(nebula * 0.3, nebula * 0.4, nebula * 0.8);

	COLOR = vec4(col, 1.0);
}
