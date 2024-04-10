//Created by Paro.
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine;

public class VolumetricClouds : ScriptableRendererFeature
{
    [System.Serializable]
    public class Settings
    {
        //future settings
        public Material material;
        public RenderPassEvent renderPassEvent = RenderPassEvent.AfterRenderingSkybox;
        public Color color = new Color(1,1,1,1);
        [Range(0, 1)]
        public float alpha = 1;
        public Vector3 BoundsMin = new Vector3(-250,50,-250);
        public Vector3 BoundsMax = new Vector3(250,80,250);
        public float RenderDistance = 1000;
    }

    [System.Serializable]
    public class CloudSettings
    {
        public int Steps = 15;
        public int LightSteps = 10;
        public Texture2D CloudNoiseTexure;
        public float CloudScale = 1;
        public float CloudSmooth = 5;
        public Vector3 Wind = new Vector3(1,0,0);
        public float LightAbsorptionThroughCloud = 0.15f;
        public Vector4 PhaseParams = new Vector4(0.1f,0.25f,0.5f,0);
        public float ContainerEdgeFadeDst = 45;
        public float DensityThreshold = 0.25f;
        public float DensityMultiplier = 1;
        public float LightAbsorptionTowardSun = 0.25f;
        public float DarknessThreshold = 0.1f;
    }

    [System.Serializable]
    public class DetailCloudSettings
    {
        [Range(0, 1)]
        public float detailCloudWeight = 0.24f;
        public Texture3D DetailCloudNoiseTexure;
        public float DetailCloudScale = 1;
        public Vector3 DetailCloudWind = new Vector3(0.5f,0,0);
    }

    [System.Serializable]
    public class BlueNoiseSettings
    {
        public Texture2D BlueNoiseTexure;
        public float RayOffsetStrength = 50;
    }

    public Settings settings = new Settings();
    public CloudSettings cloudSettings = new CloudSettings();
    public DetailCloudSettings detailCloudSettings = new DetailCloudSettings();
    public BlueNoiseSettings blueNoiseSettings = new BlueNoiseSettings();
    class Pass : ScriptableRenderPass
    {
        public Settings settings;
        public CloudSettings cloudSettings;
        public DetailCloudSettings detailCloudSettings;
        public BlueNoiseSettings blueNoiseSettings;
        private RenderTargetIdentifier source;
        RenderTargetHandle tempTexture;

        private string profilerTag;

        public void Setup(RenderTargetIdentifier source)
        {
            this.source = source;
        }

        public Pass(string profilerTag)
        {
            this.profilerTag = profilerTag;
        }

        public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
        {
            cmd.GetTemporaryRT(tempTexture.id, cameraTextureDescriptor);
            ConfigureTarget(tempTexture.Identifier());
            ConfigureClear(ClearFlag.All, Color.black);
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            CommandBuffer cmd = CommandBufferPool.Get(profilerTag);
            cmd.Clear();

            //it is very important that if something fails our code still calls 
            //CommandBufferPool.Release(cmd) or we will have a HUGE memory leak
            if(settings.material == null) return;

            try
            {
                //here we set out material properties
                //...
                settings.material.SetFloat("_alpha", settings.alpha);

                settings.material.SetColor("_color", settings.color);

                settings.material.SetVector("_BoundsMin", settings.BoundsMin);

                settings.material.SetVector("_BoundsMax", settings.BoundsMax);

                settings.material.SetFloat("_CloudScale", Mathf.Abs(cloudSettings.CloudScale));

                settings.material.SetVector("_Wind", cloudSettings.Wind);

                settings.material.SetFloat("_detailNoiseScale", Mathf.Abs(detailCloudSettings.DetailCloudScale));

                settings.material.SetVector("_detailNoiseWind", detailCloudSettings.DetailCloudWind);

                settings.material.SetFloat("_containerEdgeFadeDst", Mathf.Abs(cloudSettings.ContainerEdgeFadeDst));

                settings.material.SetTexture("_ShapeNoise", cloudSettings.CloudNoiseTexure);

                settings.material.SetTexture("_DetailNoise", detailCloudSettings.DetailCloudNoiseTexure);

                settings.material.SetFloat("_detailNoiseWeight", detailCloudSettings.detailCloudWeight);

                settings.material.SetFloat("_DensityThreshold", cloudSettings.DensityThreshold);

                settings.material.SetFloat("_DensityMultiplier", Mathf.Abs(cloudSettings.DensityMultiplier));

                settings.material.SetInteger("_NumSteps", cloudSettings.Steps);

                settings.material.SetFloat("_lightAbsorptionThroughCloud", cloudSettings.LightAbsorptionThroughCloud);

                settings.material.SetVector("_phaseParams", cloudSettings.PhaseParams);

                settings.material.SetInteger("_numStepsLight", cloudSettings.LightSteps);

                settings.material.SetFloat("_lightAbsorptionTowardSun", cloudSettings.LightAbsorptionTowardSun);

                settings.material.SetFloat("_darknessThreshold", cloudSettings.DarknessThreshold);

                settings.material.SetFloat("_cloudSmooth", cloudSettings.CloudSmooth);

                settings.material.SetTexture("_BlueNoise", blueNoiseSettings.BlueNoiseTexure);

                settings.material.SetFloat("_rayOffsetStrength", blueNoiseSettings.RayOffsetStrength);

                settings.material.SetFloat("_RenderDistance", settings.RenderDistance);

                //never use a Blit from source to source, as it only works with MSAA
                // enabled and the scene view doesnt have MSAA,
                // so the scene view will be pure black

                cmd.Blit(source, tempTexture.Identifier());
                cmd.Blit(tempTexture.Identifier(), source, settings.material, 0);

                context.ExecuteCommandBuffer(cmd);
            }
            catch
            {
                Debug.LogError("Error");
            }
            cmd.Clear();
            CommandBufferPool.Release(cmd);
        }
    }

    Pass pass;
    RenderTargetHandle renderTextureHandle;
    public override void Create()
    {
        pass = new Pass("Volumetric Clouds");
        name = "Volumetric Clouds";
        pass.settings = settings;
        pass.cloudSettings = cloudSettings;
        pass.detailCloudSettings = detailCloudSettings;
        pass.blueNoiseSettings = blueNoiseSettings;
        pass.renderPassEvent = settings.renderPassEvent;
    }
    public override void SetupRenderPasses(ScriptableRenderer renderer, in RenderingData renderingData)
    {
        var cameraColorTargetIdent = renderer.cameraColorTarget;
        pass.Setup(cameraColorTargetIdent);
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(pass);
    }
}


