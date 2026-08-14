shader_type canvas_item;

// 登录界面背景：左上角亮蓝 → 右下角深蓝的逐像素平滑渐变。
// 用 shader 逐像素计算，避免低分辨率渐变纹理放大后出现一格一格的色块。

uniform vec4 top_left_color : source_color = vec4(0.12, 0.30, 0.62, 1.0);
uniform vec4 bottom_right_color : source_color = vec4(0.02, 0.05, 0.15, 1.0);

void fragment() {
	// 对角线比例：左上角为 0，右下角为 1，中间平滑过渡
	float t = clamp((UV.x + UV.y) * 0.5, 0.0, 1.0);
	COLOR = mix(top_left_color, bottom_right_color, t);
}
