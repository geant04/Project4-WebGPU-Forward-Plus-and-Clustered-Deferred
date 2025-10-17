// TODO-2: implement the light clustering compute shader
@group(0) @binding(0) var<storage, read_write> clusterSet: ClusterSet;
@group(0) @binding(1) var<storage, read> lightSet: LightSet;
@group(0) @binding(2) var<uniform> cameraUniforms: CameraUniforms;

// ------------------------------------
// Calculating cluster bounds:
// ------------------------------------
// For each cluster (X, Y, Z):
//     - Calculate the screen-space bounds for this cluster in 2D (XY).
//     - Calculate the depth bounds for this cluster in Z (near and far planes).
//     - Convert these screen and depth bounds into view-space coordinates.
//     - Store the computed bounding box (AABB) for the cluster.


fn testAABBSphereIntersection(minAABB: vec3f, maxAABB: vec3f, position: vec3f, radius: f32) -> bool {
    // https://gdbooks.gitbooks.io/3dcollisions/content/Chapter1/closest_point_aabb.html
    // this took me a while to understand, but if the point is inside AABB, then that's exactly perfect
    let closestPoint = vec3f(
        max(min(position.x, maxAABB.x), minAABB.x),
        max(min(position.y, maxAABB.y), minAABB.y),
        max(min(position.z, maxAABB.z), minAABB.z)
    );

    let closestToSphereCenter = position - closestPoint;

    // in other words, dist^2 <= radius check
    // return position.z < maxAABB.z + radius && position.z > minAABB.z;

    return dot(closestToSphereCenter, closestToSphereCenter) <= radius * radius;
}

fn screenToView(screen: vec4f) -> vec4f {
    let texCoord = screen.xy / cameraUniforms.screenDimensions;
    let clip = vec4f(vec2f(texCoord.x, 1f - texCoord.y) * 2f - 1f, screen.z, screen.w);
    let view = cameraUniforms.invProjMat * clip;

    return view / view.w;
}

fn lineIntersectionToZPlane(a: vec3f, b: vec3f, distance: f32) -> vec3f {
    let normal = vec3f(0f, 0f, 1f);
    let ab = b - a;

    let t = (distance - dot(normal, a)) / dot(normal, ab);
    let result = a + t * ab;
    return result; 
}


@compute
@workgroup_size(1, 1, 1)
fn getClusterBounds(@builtin(global_invocation_id) globalIdx: vec3u) {
    let numClustersX = clusterSet.numClustersX;
    let numClustersY = clusterSet.numClustersY;
    let numClustersZ = clusterSet.numClustersZ;
    let numClusters = numClustersX * numClustersY * numClustersZ;

    let clusterID = globalIdx.x + (globalIdx.y * numClustersX) + (globalIdx.z * (numClustersX * numClustersY));

    if (clusterID >= numClusters)
    {
        return;
    }

    let uniformSliceLength: f32 = ${sliceLength};
    var minZ: f32 = -uniformSliceLength * f32(globalIdx.z);
    var maxZ: f32 = -uniformSliceLength * f32(globalIdx.z + 1);

    let ssMaxPoint = vec4f(vec2f(f32(globalIdx.x + 1), f32(globalIdx.y + 1)) * ${tileSize}, -1f, 1f);
    let ssMinPoint = vec4f(vec2f(f32(globalIdx.x), f32(globalIdx.y)) *  ${tileSize}, -1f, 1f);

    let viewMaxPoint = screenToView(ssMaxPoint).xyz;
    let viewMinPoint = screenToView(ssMinPoint).xyz;

    let eye = vec3f(0, 0, 0);

    let minPointNear = lineIntersectionToZPlane(eye, viewMinPoint, minZ);
    let minPointFar = lineIntersectionToZPlane(eye, viewMinPoint, maxZ);
    let maxPointNear = lineIntersectionToZPlane(eye, viewMaxPoint, minZ);
    let maxPointFar = lineIntersectionToZPlane(eye, viewMaxPoint, maxZ);

    var minPointAABB = min(min(minPointNear, minPointFar), min(maxPointNear, maxPointFar));
    var maxPointAABB = max(max(minPointNear, minPointFar), max(maxPointNear, maxPointFar));

    // Everything below this point is rock solid, I think.
    var clusterLightArrayIdx: u32 = 0;
    let maxLightsPerCluster: u32 = ${maxLightsPerCluster};

    for (var lightIdx = 0u; lightIdx < lightSet.numLights; lightIdx++) {
        let light = lightSet.lights[lightIdx];

        // Need to transform lightZ to the view Z to match the cluster's Z sapce
        var viewLightPos: vec4f = cameraUniforms.viewMat * vec4f(light.pos, 1f);

        var isIntersected: bool = testAABBSphereIntersection(minPointAABB, maxPointAABB, viewLightPos.xyz, ${lightRadius});
        if (isIntersected && clusterLightArrayIdx < maxLightsPerCluster)
        {
            // Is there a way to use references for this assignment?
            clusterSet.clusters[clusterID].lightIndices[clusterLightArrayIdx] = lightIdx;
            clusterLightArrayIdx++;
        }
    }

    clusterSet.clusters[clusterID].numLights = clusterLightArrayIdx;

    return;
}


// ------------------------------------
// Assigning lights to clusters:
// ------------------------------------
// For each cluster:
//     - Initialize a counter for the number of lights in this cluster.

//     For each light:
//         - Check if the light intersects with the cluster’s bounding box (AABB).
//         - If it does, add the light to the cluster's light list.
//         - Stop adding lights if the maximum number of lights is reached.

//     - Store the number of lights assigned to this cluster.
@compute
@workgroup_size(${moveLightsWorkgroupSize})
fn clusterLights(@builtin(global_invocation_id) globalIdx: vec3u) {
    let clusterID: u32 = globalIdx.x;

    var cluster: Cluster = clusterSet.clusters[clusterID];
    var clusterLightArrayIdx: u32 = 0;
    let maxLightsPerCluster: u32 = ${maxLightsPerCluster};

/*
    for (var lightIdx = 0u; lightIdx < lightSet.numLights; lightIdx++) {
        let light = lightSet.lights[lightIdx];

        // TO DO: more refined uhh light identification
        // Need to transform lightZ to the view Z to match the cluster's Z sapce
        var viewLightPos: vec4f = cameraUniforms.viewMat * vec4f(light.pos, 1f);
        viewLightPos.z = -viewLightPos.z;

        var isIntersected: bool = testAABBSphereIntersection(cluster.minAABB, cluster.maxAABB, viewLightPos.xyz, ${lightRadius});
        if (isIntersected && clusterLightArrayIdx < maxLightsPerCluster)
        {
            // Is there a way to use references for this assignment?
            clusterSet.clusters[clusterID].lightIndices[clusterLightArrayIdx] = lightIdx;
            clusterLightArrayIdx++;
        }
    }

    clusterSet.clusters[clusterID].numLights = clusterLightArrayIdx;
*/

    return;
}