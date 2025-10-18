// TODO-3: implement the Clustered Deferred fullscreen fragment shader

// Similar to the Forward+ fragment shader, but with vertex information coming from the G-buffer instead.
@group(0) @binding(0) var<uniform> cameraUniforms: CameraUniforms;
@group(0) @binding(1) var<storage, read> lightSet: LightSet;
@group(0) @binding(2) var<storage, read> clusterSet: ClusterSet;

@group(1) @binding(0) var normalTexture: texture_2d<f32>;
@group(1) @binding(1) var albedoTexture: texture_2d<f32>;
@group(1) @binding(2) var depthTexture: texture_2d<f32>;

fn world_from_screen_coord(coord : vec2f, depth_sample: f32) -> vec3f {
  let ndcPos = vec4(coord.x * 2.0 - 1.0, (1.0 - coord.y) * 2.0 - 1.0, depth_sample, 1.0);
  let worldW = cameraUniforms.invViewProjMat * ndcPos;
  let worldPos = worldW.xyz / worldW.www;
  return worldPos;
}

@fragment
fn main(@builtin(position) fragPos : vec4f) -> @location(0) vec4f {
    let normal: vec3f = textureLoad( normalTexture, vec2i(floor(fragPos.xy)), 0).xyz;
    let albedo: vec3f = textureLoad( albedoTexture, vec2i(floor(fragPos.xy)), 0).xyz;
    let depth: f32 = textureLoad( depthTexture, vec2i(floor(fragPos.xy)), 0 ).x;
    let position = world_from_screen_coord(fragPos.xy / vec2f(textureDimensions(depthTexture)), depth);

    let nearZ: f32 = 0.1f; //${near};
    let farZ: f32 = 5000; //${far};
    let viewDepth: f32 = (nearZ * farZ) / (farZ - depth * (farZ - nearZ));

    let tileSize = 256f; // f32(${tileSize});
    let sliceLength = 1u; // u32(${sliceLength});

    let clusterX: u32 = u32(fragPos.x / tileSize);
    let clusterY: u32 = u32(fragPos.y / tileSize);
    let clusterZ: u32 = (u32(viewDepth) / sliceLength);
    let clusterDepth: f32 = f32(clusterZ) / f32(clusterSet.numClustersZ);

    let clusterID = clusterX + (clusterY * clusterSet.numClustersX) + (clusterZ * (clusterSet.numClustersX * clusterSet.numClustersY));

    var totalLightContrib = vec3f(0, 0, 0);
    for (var clusterLightIdx = 0u; clusterLightIdx < clusterSet.clusters[clusterID].numLights; clusterLightIdx++) {
        let lightIdx = clusterSet.clusters[clusterID].lightIndices[clusterLightIdx];
        let light = lightSet.lights[lightIdx];
        totalLightContrib += calculateLightContrib(light, position, normalize(normal));
    }

    var finalColor = albedo.rgb;
    finalColor *= (totalLightContrib);

    return vec4(finalColor, 1);
}