shader_type canvas_item;

uniform sampler2D screen_buffer : hint_screen_texture, repeat_disable, filter_linear;

uniform float fade_speed = 0.000;
uniform float dynamic_fade = 0.0; // Extra fade controlled by velocity
uniform float spread_distance = 0.0;

// The exact offset representing the ship's movement this frame
uniform vec2 movement_offset = vec2(0.0);

// Safe sample guarantees returning 0.5 flat water if UV is out of bounds
// so scrolling the boat doesn't drag the black void into the center of the viewport
vec4 safe_sample(sampler2D tex, vec2 uv) {
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        return vec4(0.5, 0.5, 0.5, 1.0);
    }
    return texture(tex, uv);
}

void fragment() {
    // We shift all of our UV lookups by the ship's movement
    vec2 shifted_uv = SCREEN_UV + movement_offset;
    
    // 1. Sample the current pixel and its neighbors based on the SHIFTED coordinates
    vec4 center = safe_sample(screen_buffer, shifted_uv);
    vec4 north  = safe_sample(screen_buffer, shifted_uv + vec2(0.0, -spread_distance));
    vec4 south  = safe_sample(screen_buffer, shifted_uv + vec2(0.0, spread_distance));
    vec4 east   = safe_sample(screen_buffer, shifted_uv + vec2(spread_distance, 0.0));
    vec4 west   = safe_sample(screen_buffer, shifted_uv + vec2(-spread_distance, 0.0));
    
    // 2. Average them together to spread the wake
    vec4 blurred = (center + north + south + east + west) / 5.0;
    
    // 3. Fade toward perfectly flat water (Value 0.5)
    vec4 neutral_water = vec4(0.5, 0.5, 0.5, 1.0);
    float total_fade = clamp(fade_speed + dynamic_fade, 0.0, 1.0);
    COLOR = mix(blurred, neutral_water, total_fade);
}
