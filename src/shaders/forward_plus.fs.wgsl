@group(0) @binding(0) var<uniform> cameraUniforms: CameraUniforms;
@group(0) @binding(1) var<storage, read> lightSet: LightSet;
@group(0) @binding(2) var<storage, read> clusterSet: ClusterSet;

@group(2) @binding(0) var diffuseTex: texture_2d<f32>;
@group(2) @binding(1) var diffuseTexSampler: sampler;

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
    if (diffuseColor.a < 0.5f) {
        discard;
    }

    // Copy the light logic from naive, but just use the light indices from the accessed cluster for that
    let fragPos: vec4f = in.fragPos;
    let worldPos: vec3f = in.pos;
    let viewPos: vec4f = cameraUniforms.viewMat * vec4f(worldPos, 1f);    
    let depth: f32 = -viewPos.z;

    let tileSize = 256f; // f32(${tileSize});
    let sliceLength = 1u; // u32(${sliceLength});

    let clusterX: u32 = u32(fragPos.x / tileSize);
    let clusterY: u32 = u32(fragPos.y / tileSize);
    let clusterZ: u32 = (u32(depth) / sliceLength);
    let clusterDepth: f32 = f32(clusterZ) / f32(clusterSet.numClustersZ);

    let clusterID = clusterX + (clusterY * clusterSet.numClustersX) + (clusterZ * (clusterSet.numClustersX * clusterSet.numClustersY));

    var totalLightContrib = vec3f(0, 0, 0);
    for (var clusterLightIdx = 0u; clusterLightIdx < clusterSet.clusters[clusterID].numLights; clusterLightIdx++) {
        let lightIdx = clusterSet.clusters[clusterID].lightIndices[clusterLightIdx];
        let light = lightSet.lights[lightIdx];
        totalLightContrib += calculateLightContrib(light, in.pos, normalize(in.nor));
    }

    var finalColor = diffuseColor.rgb;
    finalColor *= (totalLightContrib);

    let notNDC = viewPos.x;

    return vec4(finalColor, 1);
    
    // Debugging stuff
    // var numLightsMapOrSomething: f32 = f32(numLights) / ${maxLightsPerCluster};
    // return vec4f(numLightsMapOrSomething, numLightsMapOrSomething, numLightsMapOrSomething, 1f);
    // return vec4(finalColor * (numLightsMapOrSomething + 0.1f), 1);
}