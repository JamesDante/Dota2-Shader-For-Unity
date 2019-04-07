// Upgrade NOTE: replaced '_Object2World' with 'unity_ObjectToWorld'
// Upgrade NOTE: replaced 'mul(UNITY_MATRIX_MVP,*)' with 'UnityObjectToClipPos(*)'

Shader "Custom/DOTA2HeroShader" {
	Properties {
		_MainTex ("Albedo (RGB)", 2D) = "white" {}
		_NormalTex ("Normal Map", 2D) = "white" {}  

		_Mask1 ("Mask 1 Texture", 2D) ="white" {}
		_Mask2 ("Mask 2 Texture", 2D) ="white" {}

		_DetailTex ("Detail Texture", 2D) ="white" {}

		//The gradients texuture
		_DiffuseWarp ("Diffuse Warp", 2D) ="white" {}
		_FresnelWarp ("Fresnel Warp Map", 2D) ="white" {}
		_FresnelColorWarp ("Fresnel Color Warp Map", 3D) ="white" {}

		_SpecularColor ("Specular Color", Color) = (1.0, 1.0, 1.0)
		_SpecularExponent ("Specular Exponent", Range(0.1, 512)) = 16  
		_SpecularScale ("Specular Scale", Range(0.1, 512)) = 1
		_Smoothness("Smoothness", Range(0.0, 1.0)) = 0.5

		_RimLightColor ("Rim Light Color", Color) = (1.0, 1.0, 1.0)
		_RimLightScale ("Rim Light Scale", Range(0.0, 32.0)) = 2.0  

		_SelfIllumStrength ("SelfIllum Strength", Range(0.0, 2.0)) = 0.1  

		_AmbientColor ("Specular Color", Color) = (1.0, 1.0, 1.0)
        _AmbientScale ("Ambient Scale", Range(0.01, 1)) = 0.5  

		[Toggle(NORMAL_ACCURATE)] _NormalAccurate ("Accurate Calculation", Int) = 1
	}
	SubShader {
	   Pass { 
	        Tags { "LightMode" = "ForwardBase"
			"Queue" = "AlphaTest"
			"IgnoreProjector" = "True"
			"RenderType" = "TransparentCutout" }  

			Cull Back
	   	        
		    //Blend SrcAlpha OneMinusSrcAlpha
			//AlphaTest Greater .5

		    CGPROGRAM  
            #pragma vertex vert  
            #pragma fragment frag  
			#pragma multi_compile_fwdbase
			#pragma shader_feature NORMAL_ACCURATE

	        #include "UnityCG.cginc"
			#include "AutoLight.cginc"
			#include "UnityStandardBRDF.cginc"

			sampler2D _MainTex; 
			sampler2D _NormalTex;
			sampler2D _Mask1;
			sampler2D _Mask2;
			sampler2D _DetailTex;
			sampler2D _DiffuseWarp;
			sampler2D _FresnelWarp;
			sampler3D _FresnelColorWarp;

			fixed3 _SpecularColor;
			half _SpecularExponent;
			half _SpecularScale;
			half _Smoothness;

			fixed3 _RimLightColor;
			float _RimLightScale;

			float _SelfIllumStrength;

			samplerCUBE _AmbientCube;
			fixed3 _AmbientColor;
			float _AmbientScale;

			struct vertexOutput 
            {
            	half4 pos	 : SV_POSITION;
            	half2 texCoord		: TEXCOORD0;
            	half3 viewDir		: TEXCOORD1;
				half3 lightDir      : TEXCOORD2;

		    #if NORMAL_ACCURATE
				half3 tSpace0	 : TEXCOORD3;
            	half3 tSpace1	 : TEXCOORD4;
            	half3 tSpace2 : TEXCOORD5;
		    #else
				half3 up      : TEXCOORD6;
		    #endif
			    LIGHTING_COORDS(7, 8)
            };

			vertexOutput vert(appdata_tan v) {  
			    vertexOutput o; 

				float4 position = float4(v.vertex.xyz, 1.0);
			    o.pos = UnityObjectToClipPos(position);
			    o.texCoord = v.texcoord;
			   
			   	half3 worldNormal = UnityObjectToWorldNormal(v.normal);
			    half3 worldTangent = UnityObjectToWorldDir(v.tangent.xyz);
			    half3 worldBinormal = cross(worldNormal, worldTangent) * v.tangent.w;

			#if NORMAL_ACCURATE
				o.lightDir = normalize(mul(unity_ObjectToWorld, ObjSpaceLightDir(v.vertex)));  
			    o.viewDir = normalize(mul(unity_ObjectToWorld, ObjSpaceViewDir(v.vertex))); 

				o.tSpace0 = fixed3(worldTangent.x, worldBinormal.x, worldNormal.x);
				o.tSpace1 = fixed3(worldTangent.y, worldBinormal.y, worldNormal.y);
				o.tSpace2 = fixed3(worldTangent.z, worldBinormal.z, worldNormal.z);
			#else
			    half3 binormal = cross(v.normal, v.tangent.xyz) * v.tangent.w;

				half3x3 rotation = float3x3(v.tangent.xyz, binormal, v.normal);
		        half3 lightDir = mul(rotation, ObjSpaceLightDir(v.vertex));  
                o.lightDir = normalize(lightDir);  
                half3 viewDir = mul(rotation, ObjSpaceViewDir(v.vertex));  
                o.viewDir = normalize(viewDir);  

				half3x3 tSpace = float3x3(normalize(worldTangent), normalize(worldBinormal), normalize(worldNormal));
				o.up = mul(tSpace, half3(.0, 1.0, .0)); 
		    #endif

			    TRANSFER_VERTEX_TO_FRAGMENT(o);  
			    return o;
			}

			fixed4 frag (vertexOutput i) : COLOR {
				half3 normalMap = UnpackNormal (tex2D(_NormalTex, i.texCoord));
				normalMap.y = -normalMap.y;
				
			#if NORMAL_ACCURATE
				half3 N = normalize(half3(dot(i.tSpace0.xyz, normalMap), dot(i.tSpace1.xyz, normalMap), dot(i.tSpace2.xyz, normalMap)));
			#else
			    half3 N = half3(normalMap.y, normalMap.x, normalMap.z);
		    #endif
				fixed3 V = i.viewDir;
			    fixed3 L =i.lightDir;
				fixed3 H = normalize(L + V);

			    half4 mask1 = tex2D(_Mask1, i.texCoord);
			    mask1 = max(mask1, fixed4(0, 1, 0, 0));
			    half4 mask2 = tex2D(_Mask2, i.texCoord);
			    
			    half flDetailMask	     = mask1.r;
	            //half flDiffuseWarpMask = mask1.g;
	            half flMetalnessMask	 = mask1.b;
	            half flSelfIllumMask	 = mask1.a;
	            
	            half flSpecularMask      = mask2.r;
	            half flRimMask           = mask2.g;
	            half flTintByBaseMask    = mask2.b;
	            half flSpecularExponent  = mask2.a;
			    
			    //Fresnel Term
			    half VdotN = saturate(dot(V, N));
				half3 fresnelTerm = tex2D(_FresnelWarp, float2(VdotN, 0.5));
			    fresnelTerm.b = max(fresnelTerm.b, mask1.b);

			    fixed3 albedo = tex2D(_MainTex, i.texCoord);
			    fixed3 diffuseColor = pow(albedo, 2.2);
			    
				//fixed3 ambient = _AmbientColor *_AmbientScale;
				//fixed3 finalDiffuse = ambient;

			    //Lighting Start
				fixed atte = LIGHT_ATTENUATION(i); 

			    half NdotL = saturate(dot(N, L));
				half NdotH = saturate(dot(N, H));
				half NdotV = saturate(dot(N, V));

			    half halfLambert = 0.5 * NdotL + 0.5;  
			    fixed3 diffuseLight = tex2D(_DiffuseWarp, half2(halfLambert, 0));
			    fixed3 finalDiffuse = diffuseLight * _LightColor0  * atte * 2;

				flSpecularExponent *= _SpecularExponent;
				half flSpecularIntensity = NdotL * pow(NdotH, flSpecularExponent);
				half3 finalSpecular = flSpecularIntensity * _LightColor0  * atte;;

				//GGX
				//float perceptualRoughness = SmoothnessToPerceptualRoughness(_Smoothness);
				//float roughness = PerceptualRoughnessToRoughness(perceptualRoughness);
				//roughness = max(roughness, 0.002);
                //float VV = SmithJointGGXVisibilityTerm(NdotL, NdotV, roughness);
                //float D = GGXTerm ( NdotH, roughness);
				//float specularTerm = VV*D * UNITY_PI;
				//specularTerm =  max(0, specularTerm * NdotL);
				//flSpecularExponent *= _SpecularExponent;
				//half3 finalSpecular = specularTerm * _LightColor0  * atte;

				//Lighting End

				half3 cSpecular = finalSpecular * _SpecularScale;
				cSpecular *= flSpecularMask;
				half3 specularTint = lerp(diffuseColor, _SpecularColor, flTintByBaseMask);
				cSpecular *= specularTint;
	            cSpecular *= fresnelTerm.b;

				half3 final = (finalDiffuse * diffuseColor);
				final += cSpecular;

			    half3 envReflection = 0.0;
	            half3 metalness = cSpecular;
	            metalness += envReflection;
	            final = lerp(final, metalness, flMetalnessMask);

				//rim-lighting
				half3 rimLighting = (fresnelTerm.r * _RimLightScale) * flRimMask; 
			    rimLighting *= saturate(dot(N, fixed3(0, 1, 0))); // Masked by a 'sky light' 
		        rimLighting *= _RimLightColor;
		        rimLighting *= (1.0 - flMetalnessMask); // Metalness
				final += rimLighting;

				//Self-Illumination
				half3 diffuseTexture = albedo.rgb * _SelfIllumStrength;
	            final += half4(diffuseTexture * flSelfIllumMask, 1.0);
				
				return half4(pow(final, 1.0/2.2), 1.0);
			}			
			ENDCG
       }
	} 
	FallBack "Diffuse"
}
