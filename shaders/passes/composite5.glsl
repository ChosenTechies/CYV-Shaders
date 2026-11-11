/////////////////////////////////////
// CYV Shaders //
/////////////////////////////////////

//Common//
#include "/cyv/cyv.glsl"

//////////Fragment Shader//////////Fragment Shader//////////Fragment Shader//////////
#ifdef FRAGMENT_SHADER

noperspective in vec2 texCoord;

#if defined BLOOM_FOG || LENSFLARE_MODE > 0 && defined OVERWORLD
    flat in vec3 upVec, sunVec;
#endif

//Pipeline Constants//

//Common Variables//
float pw = 1.0 / viewWidth;
float ph = 1.0 / viewHeight;

vec2 view = vec2(viewWidth, viewHeight);

#if defined BLOOM_FOG || LENSFLARE_MODE > 0 && defined OVERWORLD
    float SdotU = dot(sunVec, upVec);
    float sunFactor = SdotU < 0.0 ? clamp(SdotU + 0.375, 0.0, 0.75) / 0.75 : clamp(SdotU + 0.03125, 0.0, 0.0625) / 0.0625;
#endif

//Common Functions//
void LinearToRGB(inout vec3 color) {
    const vec3 k = vec3(0.055);
    color = mix((vec3(1.0) + k) * pow(color, vec3(1.0 / 2.4)) - k, 12.92 * color, lessThan(color, vec3(0.0031308)));
}

void DoCompTonemap(inout vec3 color) {
    // Lottes tonemap modified for CYV Shaders
    // Lottes 2016, "Advanced Techniques and Optimization of HDR Color Pipelines"
    // http://32ipi028l5q82yhj72224m8j.wpengine.netdna-cdn.com/wp-content/uploads/2016/03/GdcVdrLottes.pdf
    color = TM_EXPOSURE * color;

    float colorMax = max(color.r, max(color.g, color.b));
    float initialLuminance = GetLuminance(color);

    vec3 a      = vec3(TM_CONTRAST); // General Contrast
    vec3 d      = vec3(1.0); // Roll-off control
    vec3 hdrMax = vec3(8.0); // Maximum input brightness
    vec3 midIn  = vec3(0.25); // Input middle gray
    vec3 midOut = vec3(0.25); // Output middle gray

    vec3 a_d = a * d;
    vec3 hdrMaxA = pow(hdrMax, a);
    vec3 hdrMaxAD = pow(hdrMax, a_d);
    vec3 midInA = pow(midIn, a);
    vec3 midInAD = pow(midIn, a_d);
    vec3 HM1 = hdrMaxA * midOut;
    vec3 HM2 = hdrMaxAD - midInAD;

    vec3 b = (-midInA + HM1) / (HM2 * midOut);
    vec3 c = (hdrMaxAD * midInA - HM1 * midInAD) / (HM2 * midOut);

    vec3 colorOut = pow(color, a) / (pow(color, a_d) * b + c);

    LinearToRGB(colorOut);

    // Remove tonemapping from darker colors for better readability
    const float darkLiftStart = 0.1;
    const float darkLiftMix = 0.75;
    float darkLift = smoothstep(darkLiftStart, 0.0, initialLuminance);
    vec3 smoothColor = pow(color, vec3(1.0 / 2.2));
    colorOut = mix(colorOut, smoothColor, darkLift * darkLiftMix * max0(0.55 - abs(1.05 - TM_CONTRAST)) / 0.55);

    // Path to White
    const float wpInputCurveStart = 0.0;
    const float wpInputCurveMax = 16.0; // Increase this value to reduce the effect of white path
    float modifiedLuminance = pow(initialLuminance / wpInputCurveMax, 2.0 - TM_WHITE_PATH) * wpInputCurveMax;
    float whitePath = smoothstep(wpInputCurveStart, wpInputCurveMax, modifiedLuminance);
    colorOut = mix(colorOut, vec3(1.0), whitePath);

    // Desaturate dark colors
    const float dpInputCurveStart = 0.1;
    const float dpInputCurveMax = 0.0;
    float desaturatePath = smoothstep(dpInputCurveStart, dpInputCurveMax, initialLuminance);
    colorOut = mix(colorOut, vec3(GetLuminance(colorOut)), desaturatePath * TM_DARK_DESATURATION);

    color = clamp01(colorOut);
}

// CYV Tonemap, ported from CYV v10.1.8
#if TM_STYLE == 1
    mat3 CYVInverseMatrix(mat3 m) {
        float a00 = m[0][0], a01 = m[0][1], a02 = m[0][2];
        float a10 = m[1][0], a11 = m[1][1], a12 = m[1][2];
        float a20 = m[2][0], a21 = m[2][1], a22 = m[2][2];

        float b01 = a22 * a11 - a12 * a21;
        float b11 = -a22 * a10 + a12 * a20;
        float b21 = a21 * a10 - a11 * a20;

        float det = a00 * b01 + a01 * b11 + a02 * b21;

        return mat3(
            b01, (-a22 * a01 + a02 * a21), (a12 * a01 - a02 * a11),
            b11, (a22 * a00 - a02 * a20), (-a12 * a00 + a02 * a10),
            b21, (-a21 * a00 + a01 * a20), (a11 * a00 - a01 * a10)
        ) / det;
    }

    void DoCYVTonemap(inout vec3 color) {
        color *= exp2(2.0 + TM_CYV_EXPOSURE);

        float s = TM_CYV_WHITE_PATH;

        float a = 0.03 * s;
        float b = 0.01 * s;
        float c = 1.0 - (a + b);
        float d = 1.0 - (a + a);

        mat3 desatMatrix = mat3(
            vec3(c, a, b),
            vec3(a, d, a),
            vec3(b, a, c)
        );

        mat3 satMatrix = CYVInverseMatrix(desatMatrix);

        color *= desatMatrix;

        color = color / pow(pow(color, vec3(TM_CYV_WHITE_CURVE)) + 1.0, vec3(1.0 / TM_CYV_WHITE_CURVE));
        color = pow(color, mix(vec3(TM_CYV_LOWER_CURVE), vec3(TM_CYV_UPPER_CURVE), sqrt(color)));

        color *= satMatrix;

        color = clamp(color, vec3(0.0), vec3(1.0));
        color = pow(color, vec3(1.0 / 2.2)); // matches the sRGB output stage of the default pipeline
    }
#endif

void DoCYVColorSaturation(inout vec3 color) {
    float saturationFactor = T_SATURATION + 0.07;

    float grayVibrance = (color.r + color.g + color.b) / 3.0;
    float graySaturation = grayVibrance;
    if (saturationFactor < 1.00) graySaturation = dot(color, vec3(0.299, 0.587, 0.114));

    float mn = min(color.r, min(color.g, color.b));
    float mx = max(color.r, max(color.g, color.b));
    float sat = (1.0 - (mx - mn)) * (1.0 - mx) * grayVibrance * 5.0;
    vec3 lightness = vec3((mn + mx) * 0.5);

    color = mix(color, mix(color, lightness, 1.0 - T_VIBRANCE), sat);
    color = mix(color, lightness, (1.0 - lightness) * (2.0 - T_VIBRANCE) / 2.0 * abs(T_VIBRANCE - 1.0));
    color = color * saturationFactor - graySaturation * (saturationFactor - 1.0);
}

#if BLOOM_ENABLED == 1
    vec2 rescale = max(vec2(viewWidth, viewHeight) / vec2(1920.0, 1080.0), vec2(1.0));
    vec3 GetBloomTile(float lod, vec2 coord, vec2 offset) {
        float scale = exp2(lod);
        vec2 bloomCoord = coord / scale + offset;
        bloomCoord = clamp(bloomCoord, offset, 1.0 / scale + offset);

        vec3 bloom = texture2D(colortex3, bloomCoord / rescale).rgb;
        bloom *= bloom;
        bloom *= bloom;
        return bloom * 128.0;
    }

    void DoBloom(inout vec3 color, vec2 coord, float dither, float lViewPos) {
        vec3 blur1 = GetBloomTile(2.0, coord, vec2(0.0      , 0.0   ));
        vec3 blur2 = GetBloomTile(3.0, coord, vec2(0.0      , 0.26  ));
        vec3 blur3 = GetBloomTile(4.0, coord, vec2(0.135    , 0.26  ));
        vec3 blur4 = GetBloomTile(5.0, coord, vec2(0.2075   , 0.26  ));
        vec3 blur5 = GetBloomTile(6.0, coord, vec2(0.135    , 0.3325));
        vec3 blur6 = GetBloomTile(7.0, coord, vec2(0.160625 , 0.3325));
        vec3 blur7 = GetBloomTile(8.0, coord, vec2(0.1784375, 0.3325));

        #ifdef DIRTY_LENS
            float newAspectRatio = 1.777777777777778 / aspectRatio;
            vec2 dirtScale = vec2(max(newAspectRatio, 1.0), max(1.0 / newAspectRatio, 1.0));
            float dirt = texture2D(colortex14, (coord - 0.5) / dirtScale + 0.5).r;
            dirt *= length(blur6 / (1.0 + blur6));
            blur3 *= dirt *  2.0 + 1.0;
            blur4 *= dirt *  4.0 + 1.0;
            blur5 *= dirt *  8.0 + 1.0;
            blur6 *= dirt * 16.0 + 1.0;
            blur7 *= dirt * 32.0 + 1.0;
        #endif

        vec3 blur = (blur1 + blur2 + blur3 + blur4 + blur5 + blur6 + blur7) * 0.14;

        float bloomStrength = BLOOM_STRENGTH + 0.2 * darknessFactor;

        #if defined BLOOM_FOG && defined NETHER && defined BORDER_FOG
            float farM = min(renderDistance, NETHER_VIEW_LIMIT); // consistency9023HFUE85JG
            float netherBloom = lViewPos / clamp(farM, 96.0, 256.0);
            netherBloom *= netherBloom;
            netherBloom *= netherBloom;
            netherBloom = 1.0 - exp(-8.0 * netherBloom);
            netherBloom *= 1.0 - maxBlindnessDarkness;
            bloomStrength = mix(bloomStrength * 0.7, bloomStrength * 1.8, netherBloom);
        #endif

        color = mix(color, blur, bloomStrength);
        //color += blur * bloomStrength * (ditherFactor.x + ditherFactor.y);
    }
#endif

//Includes//
#ifdef BLOOM_FOG
    #include "/cyv/atmosphere/fog/bloomFog.glsl"
#endif

#if BLOOM_ENABLED == 1
    #include "/cyv/util/dither.glsl"
#endif

#ifdef RETRO_FILTER
    #include "/cyv/util/dither.glsl"
#endif

#ifdef DIRTY_LENS
    uniform sampler2D colortex14; // dirt texture
#endif

#if LENSFLARE_MODE > 0 && defined OVERWORLD
    #include "/cyv/effects/lensFlare.glsl"
#endif

//Program//
void main() {
    vec3 color = texture2D(colortex0, texCoord).rgb;

    #if defined BLOOM_FOG || LENSFLARE_MODE > 0 && defined OVERWORLD
        float z0 = texture2D(depthtex0, texCoord).r;
        vec4 screenPos = vec4(texCoord, z0, 1.0);
        vec4 viewPos = gbufferProjectionInverse * (screenPos * 2.0 - 1.0);
        viewPos /= viewPos.w;
        float lViewPos = length(viewPos.xyz);

        #if defined DISTANT_HORIZONS || defined VOXY
            #ifdef DISTANT_HORIZONS
                float z0lod = texelFetch(dhDepthTex, texelCoord, 0).r;
                vec4 screenPosLod = vec4(texCoord, z0lod, 1.0);
                vec4 viewPosLod = dhProjectionInverse * (screenPosLod * 2.0 - 1.0);
            #elif defined VOXY
                float z0lod = texelFetch(vxDepthTexTrans, texelCoord, 0).r;
                vec4 screenPosLod = vec4(texCoord, z0lod, 1.0);
                vec4 viewPosLod = vxProjInv * (screenPosLod * 2.0 - 1.0);
            #endif
            viewPosLod /= viewPosLod.w;
            lViewPos = min(lViewPos, length(viewPosLod.xyz));
        #endif
    #else
        float lViewPos = 0.0;
    #endif

    float dither = texture2DLod(noisetex, texCoord * view / 128.0, 0.0).b;
    #ifdef TAA
        dither = fract(dither + goldenRatio * mod(float(frameCounter), 3600.0));
    #endif

    #ifdef BLOOM_FOG
        color /= GetBloomFog(lViewPos);
    #endif

    #if BLOOM_ENABLED == 1
        DoBloom(color, texCoord, dither, lViewPos);
    #endif

    #ifdef COLORGRADING
        color =
            pow(color.r, GR_RC) * vec3(GR_RR, GR_RG, GR_RB) +
            pow(color.g, GR_GC) * vec3(GR_GR, GR_GG, GR_GB) +
            pow(color.b, GR_BC) * vec3(GR_BR, GR_BG, GR_BB);
        color *= 0.01;
    #endif

    #if TM_STYLE == 1
        DoCYVTonemap(color);
    #else
        DoCompTonemap(color);
    #endif

    #if defined GREEN_SCREEN_LIME || SELECT_OUTLINE == 4
        int materialMaskInt = int(texelFetch(colortex6, texelCoord, 0).g * 255.1);
    #endif

    #ifdef GREEN_SCREEN_LIME
        if (materialMaskInt == 240) { // Green Screen Lime Blocks
            color = vec3(0.0, 1.0, 0.0);
        }
    #endif

    #if SELECT_OUTLINE == 4
        if (materialMaskInt == 252) { // Versatile Selection Outline
            float colorMF = 1.0 - dot(color, vec3(0.25, 0.45, 0.1));
            colorMF = smoothstep1(smoothstep1(smoothstep1(smoothstep1(smoothstep1(colorMF)))));
            color = mix(color, 3.0 * (color + 0.2) * vec3(colorMF * SELECT_OUTLINE_I), 0.3);
        }
    #endif

    #if LENSFLARE_MODE > 0 && defined OVERWORLD
        DoLensFlare(color, viewPos.xyz, dither);
    #endif

    DoCYVColorSaturation(color);

    #ifdef RETRO_FILTER
        float retroDither = Bayer4(gl_FragCoord.xy / RETRO_FILTER_SIZE);
        color = floor(color * RETRO_FILTER_DEPTH + retroDither) / RETRO_FILTER_DEPTH;
    #endif

    /* DRAWBUFFERS:3 */
    gl_FragData[0] = vec4(color, 1.0);
}

#endif

//////////Vertex Shader//////////Vertex Shader//////////Vertex Shader//////////
#ifdef VERTEX_SHADER

noperspective out vec2 texCoord;

#if defined BLOOM_FOG || LENSFLARE_MODE > 0 && defined OVERWORLD
    flat out vec3 upVec, sunVec;
#endif

//Attributes//

//Common Variables//

//Common Functions//

//Includes//

//Program//
void main() {
    gl_Position = ftransform();

    texCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;

    #if defined BLOOM_FOG || LENSFLARE_MODE > 0 && defined OVERWORLD
        upVec = normalize(gbufferModelView[1].xyz);
        sunVec = GetSunVector();
    #endif
}

#endif
