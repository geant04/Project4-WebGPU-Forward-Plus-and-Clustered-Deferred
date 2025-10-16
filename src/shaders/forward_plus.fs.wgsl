// TODO-2: implement the Forward+ fragment shader

// See naive.fs.wgsl for basic fragment shader setup; this shader should use light clusters instead of looping over all lights

// ------------------------------------
// Shading process:
// ------------------------------------
// Determine which cluster contains the current fragment.
// Retrieve the number of lights that affect the current fragment from the cluster’s data.
// Initialize a variable to accumulate the total light contribution for the fragment.
// For each light in the cluster:
//     Access the light's properties using its index.
//     Calculate the contribution of the light based on its position, the fragment’s position, and the surface normal.
//     Add the calculated contribution to the total light accumulation.
// Multiply the fragment’s diffuse color by the accumulated light contribution.
// Return the final color, ensuring that the alpha component is set appropriately (typically to 1).

@group(${bindGroup_scene}) @binding(0) var<uniform> cameraUniforms: CameraUniforms;
@group(${bindGroup_scene}) @binding(1) var<storage, read> lightSet: LightSet;
@group(${bindGroup_scene}) @binding(2) var<storage, read> clusterSet: ClusterSet;

@group(${bindGroup_material}) @binding(0) var diffuseTex: texture_2d<f32>;
@group(${bindGroup_material}) @binding(1) var diffuseTexSampler: sampler;

@group(${bindGroup_depth}) @binding(0) var depthTex: texture_2d<f32>;
@group(${bindGroup_depth}) @binding(1) var depthTexSampler: sampler;

struct FragmentInput
{
    @builtin(position) fragPos: vec4f,
    @location(0) pos: vec3f,
    @location(1) nor: vec3f,
    @location(2) uv: vec2f
}

@fragment
fn main(in: FragmentInput) -> @location(0) vec4f
{
    let diffuseColor = textureSample(diffuseTex, diffuseTexSampler, in.uv);

    // Copy the light logic from naive, but just use the light indices from the accessed cluster for that
    let fragPos: vec4f = in.fragPos;
    let worldPos: vec3f = in.pos;
    let viewPos: vec4f = cameraUniforms.viewMat * vec4f(worldPos, 1f);    
    let depth: f32 = -viewPos.z;

    let clusterX: u32 = u32(fragPos.x / ${tileSize}); // yeah somehow convert fragPos to XY cluster
    let clusterY: u32 = u32(fragPos.y / ${tileSize});
    let clusterZ: u32 = (u32(depth) / 2u);
    let clusterDepth: f32 = f32(clusterZ) / f32(clusterSet.numClustersZ);

    // now we access our awesome.. cluster baby
    let clusterID = clusterX + (clusterY * clusterSet.numClustersX) + (clusterZ * (clusterSet.numClustersX * clusterSet.numClustersY));

    let cluster: Cluster = clusterSet.clusters[clusterID];
    let numLights: u32 = cluster.numLights;

    var totalLightContrib = vec3f(0, 0, 0);
    for (var clusterLightIdx = 0u; clusterLightIdx < numLights; clusterLightIdx++) {
        let lightIdx = cluster.lightIndices[clusterLightIdx];
        let light = lightSet.lights[lightIdx];
        totalLightContrib += calculateLightContrib(light, in.pos, normalize(in.nor));
    }

    var finalColor = diffuseColor.rgb;
    finalColor *= (totalLightContrib + vec3f(0.3, 0.3, 0.3));

    return vec4(finalColor, 1);

    //let numLightsMapOrSomething: f32 = f32(numLights) / 128f;
    //return vec4(numLightsMapOrSomething, numLightsMapOrSomething, numLightsMapOrSomething, 1);
}