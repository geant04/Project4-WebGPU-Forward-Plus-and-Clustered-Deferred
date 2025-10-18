// TODO-3: implement the Clustered Deferred G-buffer fragment shader

// This shader should only store G-buffer information and should not do any shading.

@group(0) @binding(0) var<uniform> cameraUniforms: CameraUniforms;

@group(2) @binding(0) var diffuseTex: texture_2d<f32>;
@group(2) @binding(1) var diffuseTexSampler: sampler;

struct FragmentInput
{
    @builtin(position) fragPos: vec4f,
    @location(0) pos: vec3f,
    @location(1) nor: vec3f,
    @location(2) uv: vec2f
}

struct FragmentOutput
{
    @location(0) normal: vec4f,
    @location(1) albedo: vec4f,
}

@fragment
fn main(in: FragmentInput) -> FragmentOutput
{
    var output: FragmentOutput;

    let sampledAlbedo = textureSample(diffuseTex, diffuseTexSampler, in.uv);
    
    if (sampledAlbedo.a < 0.5f)
    {
        discard;
    }

    output.normal = vec4f(in.nor, 1f);
    output.albedo= sampledAlbedo;

    return output;
}