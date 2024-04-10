//Created by Paro.
Shader "Hidden/CloudShader"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
                float3 viewDir : TEXCOORD1;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;
            sampler2D _CameraDepthTexture;
            float3 _BoundsMin, _BoundsMax;
            float _CloudScale, _detailNoiseScale;
            float3 _Wind, _detailNoiseWind;
            Texture2D<float4> _ShapeNoise;
            Texture3D<float4> _DetailNoise;
            Texture2D<float4> _BlueNoise;
            SamplerState sampler_ShapeNoise;
            SamplerState sampler_DetailNoise;
            SamplerState sampler_BlueNoise;
            float _containerEdgeFadeDst;
            float _detailNoiseWeight;
            float _DensityThreshold;
            float _DensityMultiplier;
            float _lightAbsorptionThroughCloud;
            float4 _phaseParams;
            int _NumSteps, _numStepsLight;
            float _lightAbsorptionTowardSun;
            float _darknessThreshold;
            float _cloudSmooth;
            half4 _color;
            float _alpha;
            float _rayOffsetStrength;
            float _RenderDistance;

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);

                float3 viewVector = mul(unity_CameraInvProjection, float4(v.uv * 2 - 1, 0, -1));
                o.viewDir = mul(unity_CameraToWorld, float4(viewVector,0));
                return o;
            }

            float remap(float v, float minOld, float maxOld, float minNew, float maxNew) {
                return minNew + (v-minOld) * (maxNew - minNew) / (maxOld-minOld);
            }

            float2 squareUV(float2 uv) {
                float width = _ScreenParams.x;
                float height =_ScreenParams.y;
                //float minDim = min(width, height);
                float scale = 1000;
                float x = uv.x * width;
                float y = uv.y * height;
                return float2 (x/scale, y/scale);
            }

            // Returns (dstToBox, dstInsideBox). If ray misses box, dstInsideBox will be zero
            float2 rayBoxDst(float3 boundsMin, float3 boundsMax, float3 rayOrigin, float3 invRaydir) {
                // Adapted from: http://jcgt.org/published/0007/03/04/
                float3 t0 = (boundsMin - rayOrigin) * invRaydir;
                float3 t1 = (boundsMax - rayOrigin) * invRaydir;
                float3 tmin = min(t0, t1);
                float3 tmax = max(t0, t1);
                
                float dstA = max(max(tmin.x, tmin.y), tmin.z);
                float dstB = min(tmax.x, min(tmax.y, tmax.z));

                // CASE 1: ray intersects box from outside (0 <= dstA <= dstB)
                // dstA is dst to nearest intersection, dstB dst to far intersection

                // CASE 2: ray intersects box from inside (dstA < 0 < dstB)
                // dstA is the dst to intersection behind the ray, dstB is dst to forward intersection

                // CASE 3: ray misses box (dstA > dstB)

                float dstToBox = max(0, dstA);
                float dstInsideBox = max(0, dstB - dstToBox);
                return float2(dstToBox, dstInsideBox);
            }

            float sampleDensity(float3 pos)
            {
                float3 uvw = pos * _CloudScale * 0.001 + _Wind.xyz * 0.1 * _Time.y * _CloudScale;
                float3 size = _BoundsMax - _BoundsMin;
                float3 boundsCentre = (_BoundsMin+_BoundsMax) * 0.5f;

                float3 duvw = pos * _detailNoiseScale * 0.001 + _detailNoiseWind.xyz * 0.1 * _Time.y * _detailNoiseScale;

                float dstFromEdgeX = min(_containerEdgeFadeDst, min(pos.x - _BoundsMin.x, _BoundsMax.x - pos.x));
                float dstFromEdgeY = min(_cloudSmooth, min(pos.y - _BoundsMin.y, _BoundsMax.y - pos.y));
                float dstFromEdgeZ = min(_containerEdgeFadeDst, min(pos.z - _BoundsMin.z, _BoundsMax.z - pos.z));
                float edgeWeight = min(dstFromEdgeZ,dstFromEdgeX)/_containerEdgeFadeDst;

                float4 shape = _ShapeNoise.SampleLevel(sampler_ShapeNoise, uvw.xz, 0);
                float4 detail = _DetailNoise.SampleLevel(sampler_DetailNoise, duvw, 0);
                float density = max(0, lerp(shape.x, detail.x, _detailNoiseWeight) - _DensityThreshold) * _DensityMultiplier;
                return density * edgeWeight * (dstFromEdgeY/_cloudSmooth);
            }

            // Henyey-Greenstein
            float hg(float a, float g) {
                float g2 = g*g;
                return (1-g2) / (4*3.1415*pow(1+g2-2*g*(a), 1.5));
            }

            float phase(float a) {
                float blend = .5;
                float hgBlend = hg(a,_phaseParams.x) * (1-blend) + hg(a,-_phaseParams.y) * blend;
                return _phaseParams.z + hgBlend*_phaseParams.w;
            }

            // Calculate proportion of light that reaches the given point from the lightsource
            float lightmarch(float3 position) {
                float3 dirToLight = _WorldSpaceLightPos0.xyz;
                float dstInsideBox = rayBoxDst(_BoundsMin, _BoundsMax, position, 1/dirToLight).y;
                
                float stepSize = dstInsideBox/_numStepsLight;
                float totalDensity = 0;

                for (int step = 0; step < _numStepsLight; step ++) {
                    position += dirToLight * stepSize;
                    totalDensity += max(0, sampleDensity(position) * stepSize);
                }

                float transmittance = exp(-totalDensity * _lightAbsorptionTowardSun);
                return _darknessThreshold + transmittance * (1-_darknessThreshold);
            }

            fixed4 frag (v2f i) : SV_Target
            {
                // sample the texture
                fixed4 col = tex2D(_MainTex, i.uv);

                float viewLength = length(i.viewDir);
                float3 rayOrigin = _WorldSpaceCameraPos;
                float3 rayDir = i.viewDir / viewLength;

                //Depth
                float nonlin_depth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, i.uv);
                float depth = LinearEyeDepth(nonlin_depth) * viewLength;

                float2 rayToContainerInfo = rayBoxDst(_BoundsMin, _BoundsMax, rayOrigin, 1/rayDir);
                float dstToBox = rayToContainerInfo.x;
                float dstInsideBox = rayToContainerInfo.y;
                if(dstToBox + dstInsideBox > _RenderDistance) return col;

                // random starting offset (makes low-res results noisy rather than jagged/glitchy, which is nicer)
                float randomOffset = _BlueNoise.SampleLevel(sampler_BlueNoise, squareUV(i.uv *3), 0);
                randomOffset *= _rayOffsetStrength;

                float dstTravelled = randomOffset;
                float stepSize = dstInsideBox / _NumSteps;
                float dstLimit = min(depth - dstToBox, dstInsideBox);

                float3 entryPoint = rayOrigin + rayDir * dstToBox;
                float transmittance = 1;
                float3 lightEnergy = 0;

                // Phase function makes clouds brighter around sun
                float cosAngle = dot(rayDir, _WorldSpaceLightPos0.xyz);
                float phaseVal = phase(cosAngle);

                while (dstTravelled < dstLimit) {
                    rayOrigin = entryPoint + rayDir * dstTravelled;
                    float density = sampleDensity(rayOrigin);
                    
                    if (density > 0) {
                        float lightTransmittance = lightmarch(rayOrigin);
                        lightEnergy += density * stepSize * transmittance * lightTransmittance * phaseVal;
                        transmittance *= exp(-density * stepSize * _lightAbsorptionThroughCloud);
                    
                        // Exit early if T is close to zero as further samples won't affect the result much
                        if (transmittance < 0.1) {
                            break;
                        }
                    }
                    dstTravelled += stepSize;
                }
                float3 cloudCol = lightEnergy * _color;
                float3 col0 = col * transmittance + cloudCol;
                return float4(lerp(col, col0, smoothstep(_RenderDistance, _RenderDistance * 0.25f, dstToBox + dstInsideBox) * _alpha), 0);
            }
            ENDCG
        }
    }
}
