@group(${bindGroup_scene}) @binding(0) var<uniform> cameraUniforms: CameraUniforms;
@group(${bindGroup_scene}) @binding(1) var<storage, read> lightSet: LightSet;

@group(${bindGroup_material}) @binding(0) var diffuseTex: texture_2d<f32>;
@group(${bindGroup_material}) @binding(1) var diffuseTexSampler: sampler;

struct FragmentInput
{
    @location(0) pos: vec3f,
    @location(1) nor: vec3f,
    @location(2) uv: vec2f
}

@fragment
fn main(in: FragmentInput) -> @location(0) vec4f
{
    // Position in world space
    let cameraPosition: vec3f = cameraUniforms.cameraPosition;
    let position: vec3f = in.pos;

    let normal: vec3f = in.nor;
    let uv: vec2f = in.uv;
    let roughness = 0f;
    let metallic = 0f;

    // Only one light used in this setup for now. Stick with it
    let light: Light = lightSet.lights[0];
    let lightPosition: vec3f = light.pos;

    // Define important vectors
    let wo: vec3f = normalize(cameraPosition - position);
    let wi: vec3f = normalize(lightPosition - position);

    // Diffuse component
    let diffuseLambert: f32 = max(dot(wi, normal), 0f);
    let diffuseAlbedo: vec3f = vec3f(0.85f, 0f, 0f);
    let diffuseOut = diffuseAlbedo * diffuseLambert;

    // Specular component
    let halfVector: vec3f = normalize(wi + wo);
    let phongIntensity: f32 = 1f;
    let specularPhong: f32 = phongIntensity * pow(max(dot(halfVector, normal), 0f), 20.0f);
    let specularOut: vec3f = vec3f(specularPhong);

    // Final composite
    let ambientColor: vec3f = vec3f(0.03f, 0.03f, 0.03f);
    let outColor: vec3f = diffuseOut + specularOut + ambientColor;

    return vec4(outColor, 1);
}
