shader_type canvas_item;

// 登录界面背景：深邃星空渐变
// 多层颜色叠加，模拟真实夜空的深度感

uniform vec4 color_top : source_color = vec4(0.04, 0.06, 0.18, 1.0);
uniform vec4 color_mid : source_color = vec4(0.06, 0.05, 0.20, 1.0);
uniform vec4 color_bottom : source_color = vec4(0.03, 0.03, 0.12, 1.0);

void fragment() {
	float y = UV.y;
	float x = UV.x;

	// 垂直渐变：上深蓝 → 中暗蓝紫 → 下深紫
	vec3 col;
	if (y < 0.45) {
		float t = y / 0.45;
		col = mix(color_top.rgb, color_mid.rgb, t * t);
	} else {
		float t = (y - 0.45) / 0.55;
		col = mix(color_mid.rgb, color_bottom.rgb, t);
	}

	// 水平方向微弱变化：右侧略亮（银河感），偏蓝
	float x_bias = x * 0.02;
	col += vec3(x_bias * 0.08, x_bias * 0.12, x_bias * 0.4);

	// 径向暗角：四角压暗，聚焦中心
	vec2 center = vec2(0.5, 0.45);
	float dist = distance(UV, center);
	float vignette = smoothstep(0.3, 1.1, dist);
	col *= mix(1.0, 0.6, vignette);

	COLOR = vec4(col, 1.0);
}
