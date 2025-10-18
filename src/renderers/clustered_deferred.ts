import * as renderer from '../renderer';
import * as shaders from '../shaders/shaders';

import { Stage } from '../stage/stage';

export class ClusteredDeferredRenderer extends renderer.Renderer {
    // TODO-3: add layouts, pipelines, textures, etc. needed for Forward+ here
    // you may need extra uniforms such as the camera view matrix and the canvas resolution
    sceneUniformsBindGroupLayout: GPUBindGroupLayout;
    sceneUniformsBindGroup: GPUBindGroup;

    gBufferTexturesBindGroupLayout: GPUBindGroupLayout;
    gBufferTexturesBindGroup: GPUBindGroup;

    depthTexture: GPUTexture;
    depthTextureView: GPUTextureView;
    
    normalTexture: GPUTexture;
    normalTextureView: GPUTextureView;
    
    albedoTexture: GPUTexture;
    albedoTextureView: GPUTextureView;

    deferredPipeline: GPURenderPipeline;
    shadingPipeline: GPURenderPipeline;

    constructor(stage: Stage) {
        super(stage);

        // TODO-3: initialize layouts, pipelines, textures, etc. needed for Forward+ here
        // you'll need two pipelines: one for the G-buffer pass and one for the fullscreen pass
        this.sceneUniformsBindGroupLayout = renderer.device.createBindGroupLayout({
            label: "scene uniforms bind group layout",
            entries: [
                {
                    binding: 0,
                    visibility: GPUShaderStage.VERTEX | GPUShaderStage.FRAGMENT,
                    buffer: { type: "uniform"}
                },
                { // lightSet
                    binding: 1,
                    visibility: GPUShaderStage.FRAGMENT,
                    buffer: { type: "read-only-storage" }
                },
                { // clusterSet
                    binding: 2,
                    visibility: GPUShaderStage.FRAGMENT,
                    buffer: { type: "read-only-storage" }
                }
            ]
        });

        this.sceneUniformsBindGroup = renderer.device.createBindGroup({
            label: "scene uniforms bind group",
            layout: this.sceneUniformsBindGroupLayout,
            entries: [
                {
                    binding: 0,
                    resource: { buffer: this.camera.uniformsBuffer }
                },
                {
                    binding: 1,
                    resource: { buffer: this.lights.lightSetStorageBuffer }
                },
                {
                    binding: 2,
                    resource: { buffer: this.lights.clusterSetStorageBuffer }
                }
            ]
        });

        this.depthTexture = renderer.device.createTexture({
            size: [renderer.canvas.width, renderer.canvas.height],
            format: "depth24plus",
            usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.TEXTURE_BINDING
        });
        this.depthTextureView = this.depthTexture.createView();

        this.normalTexture = renderer.device.createTexture({
            size: [renderer.canvas.width, renderer.canvas.height],
            format: "rgba16float",
            usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.TEXTURE_BINDING
        })
        this.normalTextureView = this.normalTexture.createView();

        this.albedoTexture = renderer.device.createTexture({
            size: [renderer.canvas.width, renderer.canvas.height],
            format: "bgra8unorm",
            usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.TEXTURE_BINDING
        })
        this.albedoTextureView = this.albedoTexture.createView();
        
        
        // uhh yeah idk what's going on but i'm just copying the deferred tutorial stuff
        this.gBufferTexturesBindGroupLayout = renderer.device.createBindGroupLayout({
        entries: [
            {
            binding: 0,
            visibility: GPUShaderStage.FRAGMENT,
            texture: {
                sampleType: 'unfilterable-float',
            },
            },
            {
            binding: 1,
            visibility: GPUShaderStage.FRAGMENT,
            texture: {
                sampleType: 'unfilterable-float',
            },
            },
            {
            binding: 2,
            visibility: GPUShaderStage.FRAGMENT,
            texture: {
                sampleType: 'unfilterable-float',
            },
            },
        ],
        });

        this.gBufferTexturesBindGroup = renderer.device.createBindGroup({
            layout: this.gBufferTexturesBindGroupLayout,
            entries: [
                {
                    binding: 0,
                    resource: this.normalTextureView
                },
                {
                    binding: 1,
                    resource: this.albedoTextureView
                },
                {
                    binding: 2,
                    resource: this.depthTextureView
                }
            ]
        });

        this.deferredPipeline = renderer.device.createRenderPipeline({
            layout: renderer.device.createPipelineLayout({
                label: "naive pipeline layout",
                bindGroupLayouts: [
                    this.sceneUniformsBindGroupLayout,
                    renderer.modelBindGroupLayout,
                    renderer.materialBindGroupLayout
                ]
            }),
            depthStencil: {
                depthWriteEnabled: true,
                depthCompare: "less",
                format: "depth24plus"
            },
            vertex: {
                module: renderer.device.createShaderModule({
                    label: "clustered deferred (same as naive vert) shader",
                    code: shaders.naiveVertSrc
                }),
                buffers: [ renderer.vertexBufferLayout ]
            },
            fragment: {
                module: renderer.device.createShaderModule({
                    label: "clustered deferred frag shader",
                    code: shaders.clusteredDeferredFragSrc,
                }),
                targets: [
                    {
                        format: "rgba16float", // normals
                    },
                    {
                        format: "bgra8unorm"
                    }
                ]
            }
        });

        this.shadingPipeline = renderer.device.createRenderPipeline({
            label: "shading pipeline",
            layout: renderer.device.createPipelineLayout({
                label: "fullscreen pipeline pass",
                bindGroupLayouts: [
                    this.sceneUniformsBindGroupLayout,
                    this.gBufferTexturesBindGroupLayout
                ]
            }),
            vertex: {
                module: renderer.device.createShaderModule({
                    label: "clustered deferred fullscreen vert pass",
                    code: shaders.clusteredDeferredFullscreenVertSrc
                })
            },
            fragment: {
                module: renderer.device.createShaderModule({
                    label: "clustered deferred fullscreen frag pass",
                    code: shaders.clusteredDeferredFullscreenFragSrc
                }),
                targets: [
                    {
                        format: renderer.canvasFormat
                    }
                ]
            }
        });

    }

    override draw() {
        // TODO-3: run the Forward+ rendering pass:
        // - run the clustering compute shader
        // - run the G-buffer pass, outputting position, albedo, and normals
        // - run the fullscreen pass, which reads from the G-buffer and performs lighting calculations

        const encoder = renderer.device.createCommandEncoder();
        const canvasTextureView = renderer.context.getCurrentTexture().createView();

        // call clustering compute shader...
        this.lights.doLightClustering(encoder);

        const deferredPass = encoder.beginRenderPass({
            label: "deferred render pass",
            colorAttachments: [
                {
                    view: this.normalTextureView,
                    clearValue: [0, 0, 1, 1,],
                    loadOp: "clear",
                    storeOp: "store"
                },
                {
                    view: this.albedoTextureView,
                    clearValue: [0, 0, 0, 1],
                    loadOp: "clear",
                    storeOp: "store"
                }
            ],
            depthStencilAttachment: {
                view: this.depthTextureView,
                depthClearValue: 1.0,
                depthLoadOp: "clear",
                depthStoreOp: "store"
            }
        });

        deferredPass.setPipeline(this.deferredPipeline);
        deferredPass.setBindGroup(shaders.constants.bindGroup_scene, this.sceneUniformsBindGroup);

        this.scene.iterate(node => {
            deferredPass.setBindGroup(shaders.constants.bindGroup_model, node.modelBindGroup);
        }, material => {
            deferredPass.setBindGroup(shaders.constants.bindGroup_material, material.materialBindGroup);
        }, primitive => {
            deferredPass.setVertexBuffer(0, primitive.vertexBuffer);
            deferredPass.setIndexBuffer(primitive.indexBuffer, 'uint32');
            deferredPass.drawIndexed(primitive.numIndices);
        });

        deferredPass.end();

        const shadingPass = encoder.beginRenderPass({
            label: "fullscreen pass",
            colorAttachments: [
                {
                    view: canvasTextureView,
                    clearValue: [0, 0, 0, 0],
                    loadOp: "clear",
                    storeOp: "store"
                }
            ]
        });

        shadingPass.setPipeline(this.shadingPipeline);
        shadingPass.setBindGroup(0, this.sceneUniformsBindGroup);
        shadingPass.setBindGroup(1, this.gBufferTexturesBindGroup);
        shadingPass.draw(6);

        shadingPass.end();

        renderer.device.queue.submit([encoder.finish()]);
    }
}
