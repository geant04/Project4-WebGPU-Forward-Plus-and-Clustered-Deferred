import { vec3 } from "wgpu-matrix";
import { canvas, device } from "../renderer";

import * as shaders from '../shaders/shaders';
import { Camera } from "./camera";

// h in [0, 1]
function hueToRgb(h: number) {
    let f = (n: number, k = (n + h * 6) % 6) => 1 - Math.max(Math.min(k, 4 - k, 1), 0);
    return vec3.lerp(vec3.create(1, 1, 1), vec3.create(f(5), f(3), f(1)), 0.8);
}

export class Lights {
    private camera: Camera;

    numLights = 10000;
    static readonly maxNumLights = 10000;
    static readonly numFloatsPerLight = 8; // vec3f is aligned at 16 byte boundaries

    static readonly lightIntensity = 0.1;

    lightsArray = new Float32Array(Lights.maxNumLights * Lights.numFloatsPerLight);
    lightSetStorageBuffer: GPUBuffer;

    timeUniformBuffer: GPUBuffer;

    moveLightsComputeBindGroupLayout: GPUBindGroupLayout;
    moveLightsComputeBindGroup: GPUBindGroup;
    moveLightsComputePipeline: GPUComputePipeline;

    // TODO-2: add layouts, pipelines, textures, etc. needed for light clustering here
    maxLightsPerCluster = shaders.constants.maxLightsPerCluster;

    // let our slice length be 2, arbitrarily ig
    slices = shaders.constants.numSlices;

    maxDepth = 20;

    // this needs to change ngl
    screenWidth = canvas.width;
    screenHeight = canvas.height;

    totalPixels = this.screenWidth * this.screenHeight;

    tileWidth = shaders.constants.tileSize;
    tileHeight = shaders.constants.tileSize;

    numClustersX = Math.ceil(this.screenWidth / this.tileWidth);
    numClustersY = Math.ceil(this.screenHeight / this.tileHeight);
    numClustersZ = this.slices;

    maxNumClusters = this.numClustersX * this.numClustersY * this.numClustersZ;
    floatsPerCluster = 1 + shaders.constants.maxLightsPerCluster;

    clustersArray = new Float32Array(this.maxNumClusters * this.floatsPerCluster);
    clusterSetStorageBuffer: GPUBuffer;

    getClusterBoundsComputeBindGroupLayout: GPUBindGroupLayout;
    getClusterBoundsComputeBindGroup: GPUBindGroup;
    getClusterBoundsComputePipeline: GPUComputePipeline;

    clusterLightsComputePipeline: GPUComputePipeline;

    debugStopLights = false;
    
    constructor(camera: Camera) {
        this.camera = camera;

        console.log(this.numClustersX);
        console.log(this.numClustersY);
        console.log(this.numClustersZ);

        console.log(this.maxNumClusters);

        this.lightSetStorageBuffer = device.createBuffer({
            label: "lights",
            size: 16 + this.lightsArray.byteLength, // 16 for numLights + padding
            usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST
        });
        this.populateLightsBuffer();
        this.updateLightSetUniformNumLights();

        // shrimple cluster buffer construction
        // need u32s for numClusters X, Y, and Z, maxLightsPerCluster, and numLights
        let clusterSetInfoSize = 16 * 5;

        this.clusterSetStorageBuffer = device.createBuffer({
            label: "clusters",
            size: clusterSetInfoSize + this.clustersArray.byteLength, // DEBUG POINT: potential error coming from here
            usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST
        });

        this.timeUniformBuffer = device.createBuffer({
            label: "time uniform",
            size: 4,
            usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST
        });

        this.moveLightsComputeBindGroupLayout = device.createBindGroupLayout({
            label: "move lights compute bind group layout",
            entries: [
                { // lightSet
                    binding: 0,
                    visibility: GPUShaderStage.COMPUTE,
                    buffer: { type: "storage" }
                },
                { // time
                    binding: 1,
                    visibility: GPUShaderStage.COMPUTE,
                    buffer: { type: "uniform" }
                }
            ]
        });

        this.moveLightsComputeBindGroup = device.createBindGroup({
            label: "move lights compute bind group",
            layout: this.moveLightsComputeBindGroupLayout,
            entries: [
                {
                    binding: 0,
                    resource: { buffer: this.lightSetStorageBuffer }
                },
                {
                    binding: 1,
                    resource: { buffer: this.timeUniformBuffer }
                }
            ]
        });

        this.moveLightsComputePipeline = device.createComputePipeline({
            label: "move lights compute pipeline",
            layout: device.createPipelineLayout({
                label: "move lights compute pipeline layout",
                bindGroupLayouts: [ this.moveLightsComputeBindGroupLayout ]
            }),
            compute: {
                module: device.createShaderModule({
                    label: "move lights compute shader",
                    code: shaders.moveLightsComputeSrc
                }),
                entryPoint: "main"
            }
        });

        // TODO-2: initialize layouts, pipelines, textures, etc. needed for light clustering here
        device.queue.writeBuffer(
            this.clusterSetStorageBuffer, 
            0, 
            new Uint32Array([this.numClustersX, this.numClustersY, this.numClustersZ, this.maxLightsPerCluster]));

        this.getClusterBoundsComputeBindGroupLayout = device.createBindGroupLayout({
            label: "get cluster bounds compute bind group layout",
            entries: [
                {
                    binding: 0,
                    visibility: GPUShaderStage.COMPUTE,
                    buffer: { type: "storage" }
                },
                {
                    binding: 1,
                    visibility: GPUShaderStage.COMPUTE,
                    buffer: { type: "read-only-storage" }
                },
                {
                    binding: 2,
                    visibility: GPUShaderStage.COMPUTE,
                    buffer: { type: "uniform" }
                }
            ]
        });

        this.getClusterBoundsComputeBindGroup = device.createBindGroup({
            label: "get cluster bounds compute bind group",
            layout: this.getClusterBoundsComputeBindGroupLayout,
            entries: [
                {
                    binding: 0,
                    resource: { buffer: this.clusterSetStorageBuffer }
                },
                {
                    binding: 1,
                    resource: { buffer: this.lightSetStorageBuffer }
                },
                {
                    binding: 2,
                    resource: { buffer: this.camera.uniformsBuffer }
                }
            ]
        });

        this.getClusterBoundsComputePipeline = device.createComputePipeline({
            label: "get cluster bounds compute pipeline",
            layout: device.createPipelineLayout({
                label: "get cluster bounds compute pipeline layout",
                bindGroupLayouts: [ this.getClusterBoundsComputeBindGroupLayout ]
            }),
            compute: {
                module: device.createShaderModule({
                    label: "get cluster bounds compute shader",
                    code: shaders.clusteringComputeSrc
                }),
                entryPoint: "getClusterBounds"
            }
        });

        this.clusterLightsComputePipeline = device.createComputePipeline({
            label: "cluster lights compute pipeline",
            layout: device.createPipelineLayout({
                label: "cluster lights compute pipeline layout",
                bindGroupLayouts: [ this.getClusterBoundsComputeBindGroupLayout ]
            }),
            compute: {
                module: device.createShaderModule({
                    label: "cluster lights compute shader",
                    code: shaders.clusteringComputeSrc
                }),
                entryPoint: "clusterLights"
            }
        });
    }

    private populateLightsBuffer() {
        for (let lightIdx = 0; lightIdx < Lights.maxNumLights; ++lightIdx) {
            // light pos is set by compute shader so no need to set it here
            const lightColor = vec3.scale(hueToRgb(Math.random()), Lights.lightIntensity);
            this.lightsArray.set(lightColor, (lightIdx * Lights.numFloatsPerLight) + 4);
        }

        device.queue.writeBuffer(this.lightSetStorageBuffer, 16, this.lightsArray);
    }

    updateLightSetUniformNumLights() {
        device.queue.writeBuffer(this.lightSetStorageBuffer, 0, new Uint32Array([this.numLights]));
    }

    doLightClustering(encoder: GPUCommandEncoder) {
        // TODO-2: run the light clustering compute pass(es) here
        // implementing clustering here allows for reusing the code in both Forward+ and Clustered Deferred
        const computePass = encoder.beginComputePass();
        computePass.setPipeline(this.getClusterBoundsComputePipeline);
        computePass.setBindGroup(0, this.getClusterBoundsComputeBindGroup); // switched my bind group to 1... don't know what this does

        const workgroupX = Math.ceil(this.numClustersX / shaders.constants.clusterLightsWorkgroupX);
        const workgroupY = Math.ceil(this.numClustersY / shaders.constants.clusterLightsWorkgroupY);
        const workgroupZ = Math.ceil(this.numClustersZ / shaders.constants.clusterLightsWorkgroupZ);

        computePass.dispatchWorkgroups(workgroupX, workgroupY, workgroupZ);

        computePass.end();
    }

    // CHECKITOUT: this is where the light movement compute shader is dispatched from the host
    onFrame(time: number) {
        if (this.debugStopLights && shaders.constants.performanceTesting)
        {
            return;
        }

        this.debugStopLights = !this.debugStopLights;

        device.queue.writeBuffer(this.timeUniformBuffer, 0, new Float32Array([time]));

        // not using same encoder as render pass so this doesn't interfere with measuring actual rendering performance
        const encoder = device.createCommandEncoder();

        const computePass = encoder.beginComputePass();
        computePass.setPipeline(this.moveLightsComputePipeline);

        computePass.setBindGroup(0, this.moveLightsComputeBindGroup);

        const workgroupCount = Math.ceil(this.numLights / shaders.constants.moveLightsWorkgroupSize);
        computePass.dispatchWorkgroups(workgroupCount);

        computePass.end();

        device.queue.submit([encoder.finish()]);
    }
}
