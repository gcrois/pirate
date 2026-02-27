shader_type canvas_item;

uniform vec3 ship_position = vec3(0.0);
uniform mat3 ship_basis = mat3(1.0); // 3x3 rotation matrix of the ship
uniform vec3 ship_velocity = vec3(0.0);
uniform float ship_speed = 0.0;
uniform float ocean_size_meters = 100.0;

// Ship dimensions
uniform float ship_half_length = 4.5;
uniform float ship_half_width  = 1.75;
uniform float ship_draft = 1.0; // How deep the hull goes underwater

// Identical to ocean shader to compute surface height
uniform float wave_height = 0.8;
uniform float wave_speed  = 1.0;
uniform float wave_scale  = 0.25;

float get_wave(vec2 p, float t) {
	float s = wave_scale;
	float h = wave_height;
	float w = 0.0;
	w += sin(dot(vec2( 0.800,  0.600), p) * s * 1.00 + t * 1.00) * h * 1.000;
	w += sin(dot(vec2( 0.980,  0.200), p) * s * 1.60 + t * 0.80) * h * 0.600;
	w += sin(dot(vec2( 0.195,  0.981), p) * s * 2.20 + t * 1.30) * h * 0.350;
	w += sin(dot(vec2(-0.686,  0.728), p) * s * 3.80 + t * 2.00) * h * 0.180;
	w += sin(dot(vec2( 0.530, -0.848), p) * s * 6.50 + t * 2.60) * h * 0.090;
	w += sin(dot(vec2(-0.978,  0.208), p) * s * 10.0 + t * 1.50) * h * 0.045;
	return w;
}

void fragment() {
    // 1. Calculate the world XZ coordinate of this pixel
    // UV goes 0 to 1, representing ship_position - 50m to ship_position + 50m
    vec2 world_xz = ship_position.xz + (UV - vec2(0.5)) * ocean_size_meters;
    
    // 2. Sample the local wave height at this exact point
    float t = TIME * wave_speed;
    float current_wave_h = get_wave(world_xz, t);
    
    // 3. Transform the world XZ into the ship's LOCAL coordinate space.
    // We treat the ship's center as (0, 0), +Z is backward, -Z is forward, X is left/right.
    // Inverse multiply 3D rotation onto a 2D vector for simplified bounding box projection
    vec3 to_pixel = vec3(world_xz.x - ship_position.x, 0.0, world_xz.y - ship_position.z);
    
    // To go from world -> local, we multiply by the transpose (inverse of rotation matrix)
    vec3 local_pos = to_pixel * ship_basis; 
    
    // Calculate an elliptical hull shape in local XZ
    float hull_x = local_pos.x / ship_half_width;  // Lateral width
    float hull_z = local_pos.z / ship_half_length; // Forward/Backward length
    float hull_radius_sq = hull_x * hull_x + hull_z * hull_z;
    
    // Let's establish the Hull's physical bottom height (assuming ship node sits at water rest level)
    float hull_bottom_y = ship_position.y - ship_draft;
    
    // Only process if we are underneath the ship footprint
    if (hull_radius_sq <= 1.0) {
        
        // Let's curve the hull upwards towards the edges
        float curved_hull_y = hull_bottom_y + hull_radius_sq * ship_draft;
        
        // If the hull point is lower than the water surface, we are submerged!
        float intersection_depth = current_wave_h - curved_hull_y;
        
        if (intersection_depth > 0.0) {
            // -- WE ARE IN THE WATER --
            
            // 1. We create the TRENCH directly underneath (black)
            // Displacement target is 0.0 (fully pushes down). 
            // 0.5 is neutral gray.
            float target_val = max(0.0, 0.5 - (intersection_depth * 0.25));
            
            // 2. Determine FRONT vs BACK. 
            // In Godot, -Z is forward. So local_pos.z < 0 is the bow.
            // When moving forward, the bow *pushes* water, raising it (white).
            // A simple implementation: Dot product of local position and ship velocity.
            vec3 local_vel = ship_velocity * ship_basis; 
            
            // Are we on the side of the ship pushing water?
            float push_factor = dot(normalize(local_pos), normalize(local_vel + vec3(0.0, 0.0, 0.001)));
            
            if (push_factor > 0.0 && ship_speed > 0.5) {
                // Pushing water! Turn it white.
                float push_force = push_factor * clamp(ship_speed / 5.0, 0.0, 1.0);
                target_val = mix(target_val, 1.0, push_force);
            }
            
            COLOR = vec4(target_val, target_val, target_val, 1.0);
        } else {
            // Not intersecting, emit 0.5 alpha so feedback buffer remains visible
            COLOR = vec4(0.5, 0.5, 0.5, 0.0);
        }
    } else {
        // Outside the hull
        COLOR = vec4(0.5, 0.5, 0.5, 0.0);
    }
}
