// CYV-style volumetric slab clouds
// Custom slab cloud implementation for the CYV pipeline.

#if CLOUD_QUALITY == 1 || !defined DEFERRED1
    const float cloudNarrowness = 0.00006;
#else
    const float cloudNarrowness = 0.00012;
#endif

//Sampling//

float CloudSampleBasePerlin(vec2 coord) {
    return texture2DLod(noisetex, coord, 0.0).r;
}

float CloudSampleBaseWorley(vec2 coord) {
    float noiseBase = texture2DLod(noisetex, coord, 0.0).g;
    noiseBase = pow(1.0 - noiseBase, 2.0) * 0.5 + 0.25;

    return noiseBase;
}

float CloudSampleBaseBlocky(vec2 coord) {
    float noiseRes = 512.0;

    coord.xy = coord.xy * noiseRes - 0.5;

    vec2 flr = floor(coord.xy);
    vec2 frc = coord.xy - flr;

    frc = clamp(frc * 5.0 - 2.0, vec2(0.0), vec2(1.0));
    frc = frc * frc * (3.0 - 2.0 * frc);

    coord.xy = (flr + frc + 0.5) / noiseRes;

    float noiseBase = texture2DLod(noisetex, coord, 0.0).a;
    noiseBase = (1.0 - noiseBase) * 4.0;

    float noiseRain = texture2DLod(noisetex, coord + vec2(0.5, 0.0), 0.0).a;
    noiseRain = (1.0 - noiseRain) * 4.0 * smoothstep(0.0, 0.5, rainStrength);

    noiseBase = min(noiseBase + noiseRain, 1.0);

    return noiseBase;
}

float CloudSampleDetail(vec2 coord, float cloudGradient) {
    float detailZ = floor(cloudGradient * float(CLOUD_CYV_THICKNESS)) * 0.04;
    float detailFrac = fract(cloudGradient * float(CLOUD_CYV_THICKNESS));

    float noiseDetailLow  = texture2DLod(noisetex, coord.xy + detailZ, 0.0).b;
    float noiseDetailHigh = texture2DLod(noisetex, coord.xy + detailZ + 0.04, 0.0).b;

    float noiseDetail = mix(noiseDetailLow, noiseDetailHigh, detailFrac);

    return noiseDetail;
}

float CloudCoverageDefault(float cloudGradient) {
    float noiseCoverage = abs(cloudGradient - 0.125);

    noiseCoverage *= cloudGradient > 0.125 ? (2.14 - CLOUD_CYV_AMOUNT * 0.1) : 8.0;
    noiseCoverage = noiseCoverage * noiseCoverage * 4.0;

    return noiseCoverage;
}

float CloudCoverageBlocky(float cloudGradient) {
    float noiseCoverage = abs(cloudGradient - 0.5) * 2.0;

    noiseCoverage *= noiseCoverage;
    noiseCoverage *= noiseCoverage;

    return noiseCoverage;
}

float CloudApplyDensity(float noise) {
    noise *= CLOUD_CYV_DENSITY * 0.125;
    noise *= 1.0 - 0.75 * rainStrength;
    noise = noise / sqrt(noise * noise + 0.5);

    return noise;
}

float CloudCombineDefault(float noiseBase, float noiseDetail, float noiseCoverage) {
    float noise = mix(noiseBase, noiseDetail, 0.0476 * CLOUD_CYV_DETAIL) * 21.0;

    noise = mix(noise - noiseCoverage, 21.0 - noiseCoverage * 2.5, 0.33 * rainStrength);
    noise = max(noise - CLOUD_CYV_AMOUNT, 0.0);

    noise = CloudApplyDensity(noise);

    return noise;
}

float CloudCombineBlocky(float noiseBase, float noiseCoverage) {
    float noise = (noiseBase - noiseCoverage) * 2.0;

    noise = max(noise, 0.0);

    noise = CloudApplyDensity(noise);

    return noise;
}

float CloudSample(vec2 coord, vec2 wind, float cloudGradient) {
    coord *= 0.004 * CLOUD_CYV_STRETCH;

    #if CLOUD_CYV_BASE == 0
        vec2 baseCoord = coord * 0.25 + wind;
        vec2 detailCoord = coord.xy * 0.5 - wind * 2.0;

        float noiseBase = CloudSampleBasePerlin(baseCoord);
        float noiseDetail = CloudSampleDetail(detailCoord, cloudGradient);
        float noiseCoverage = CloudCoverageDefault(cloudGradient);

        return CloudCombineDefault(noiseBase, noiseDetail, noiseCoverage);
    #elif CLOUD_CYV_BASE == 1
        vec2 baseCoord = coord * 0.5 + wind * 2.0;
        vec2 detailCoord = coord.xy * 0.5 - wind * 2.0;

        float noiseBase = CloudSampleBaseWorley(baseCoord);
        float noiseDetail = CloudSampleDetail(detailCoord, cloudGradient);
        float noiseCoverage = CloudCoverageDefault(cloudGradient);

        return CloudCombineDefault(noiseBase, noiseDetail, noiseCoverage);
    #else
        vec2 baseCoord = coord * 0.15625 + wind * 0.5;

        float noiseBase = CloudSampleBaseBlocky(baseCoord);
        float noiseCoverage = CloudCoverageBlocky(cloudGradient);

        return CloudCombineBlocky(noiseBase, noiseCoverage);
    #endif
}

float InvLerp(float v, float l, float h) {
    return clamp((v - l) / (h - l), 0.0, 1.0);
}

//Rendering//

vec4 GetCYVClouds(inout float cloudLinearDepth, float skyFade, float skyMult0, vec3 cameraPos, vec3 nPlayerPos,
                  float lViewPosM, float VdotS, float VdotU, float dither) {
    vec4 volumetricClouds = vec4(0.0);

    float cloudThickness = float(CLOUD_CYV_THICKNESS);
    int maxSamples = 32;

    #if CLOUD_CYV_BASE == 2
        cloudThickness *= 0.4;
        maxSamples = 64;
    #endif

    float lowerY = float(cloudAlt1i);
    float upperY = lowerY + cloudThickness * CLOUD_CYV_SCALE;

    float lowerPlaneDistance = (lowerY - cameraPos.y) / nPlayerPos.y;
    float upperPlaneDistance = (upperY - cameraPos.y) / nPlayerPos.y;
    float minPlaneDistance = max(min(lowerPlaneDistance, upperPlaneDistance), 0.0);
    float maxPlaneDistance = max(lowerPlaneDistance, upperPlaneDistance);
    if (maxPlaneDistance < 0.0) return vec4(0.0);
    float planeDistanceDif = maxPlaneDistance - minPlaneDistance;

    float aboveClouds = clamp01((cameraPos.y - lowerY) * 0.01);
    float skyFadeM = mix(skyFade, 1.0, 0.4 * max(aboveClouds, rainFactor2));

    float lengthScaling = abs(cameraPos.y - (upperY + lowerY) * 0.5) / ((upperY - lowerY) * 0.5);
    lengthScaling = clamp((lengthScaling - 1.0) * cloudThickness * 0.125, 0.0, 1.0);

    float sampleLength = cloudThickness * CLOUD_CYV_SCALE / 2.0;
    sampleLength /= (4.0 * nPlayerPos.y * nPlayerPos.y) * lengthScaling + 1.0;
    vec3 sampleStep = nPlayerPos * sampleLength;
    int samples = int(min(planeDistanceDif / sampleLength, float(maxSamples)) + 1.0);

    vec3 samplePos = cameraPos + minPlaneDistance * nPlayerPos + sampleStep * dither;
    float sampleTotalLength = minPlaneDistance + sampleLength * dither;

    float distanceThreshold = 4000.0;
    float firstHitPos = 0.0;

    #define CLOUD_SPEED_MULT_M CLOUD_SPEED_MULT * 0.01
    vec2 wind = vec2(
        syncedTime * 0.0005,
        sin(syncedTime * 0.001) * 0.005
    ) * 0.667 * CLOUD_SPEED_MULT_M;

    vec3 lightVec = sunVec * ((timeAngle < 0.5325 || timeAngle > 0.9675) ? 1.0 : -1.0);

    float VoL = dot(nPlayerPos, lightVec);
    float halfVoL = VoL * 0.5 + 0.5;
    float halfVoLSqr = halfVoL * halfVoL;

    float scattering = pow(halfVoL, 6.0);
    float noiseLightFactor = (2.0 - 1.5 * VoL * sunVisibility) * CLOUD_CYV_DENSITY * 0.5;

    float xzNormalizeFactor = 10.0 / max(abs(float(cloudAlt1i) - 72.0), 56.0);

    float VdotSM1 = max0(sunVisibility > 0.5 ? VdotS : -VdotS);
    float VdotSM1M = VdotSM1 * invRainFactor;

    for (int i = 0; i < samples; i++) {
        if (volumetricClouds.a > 0.9) break;

        float cloudGradient = InvLerp(samplePos.y, lowerY, upperY);
        float lTracePosXZ = length(samplePos.xz - cameraPos.xz);
        float xzNormalizedDistance = lTracePosXZ * xzNormalizeFactor;
        vec2 cloudCoord = samplePos.xz / CLOUD_CYV_SCALE;

        float noise = CloudSample(cloudCoord, wind, cloudGradient);
        noise *= step(lowerY, samplePos.y) * step(samplePos.y, upperY);

        float cloudMult = 1.0;
        if (lTracePosXZ > distanceThreshold) break;
        if (sampleTotalLength > lViewPosM) {
            if (skyFade < 0.7) continue;
            else cloudMult = skyMult0;
        }

        if (noise > 0.00001) {
            if (firstHitPos < 1.0) firstHitPos = sampleTotalLength;

            float opacityFactor = min1(noise * 8.0);

            float sampleLighting = pow(cloudGradient, 1.125 * halfVoLSqr + 0.875) * 0.8 + 0.2;
            sampleLighting *= 1.0 - pow(noise, noiseLightFactor);

            float distanceRatio = (distanceThreshold - lTracePosXZ) / distanceThreshold;
            float cloudDistanceFactor = clamp(distanceRatio, 0.0, 0.8) * 1.25;
            float cloudFogFactor = pow2(pow1_5(clamp(distanceRatio, 0.0, 1.0))) * 0.69;
            cloudFogFactor = mix(1.0, cloudFogFactor, skyFadeM);

            vec3 cloudSkyColor = GetSky(VdotU, VdotS, dither, isEyeInWater == 0, false);
            #ifdef ATM_COLOR_MULTS
                cloudSkyColor *= sqrtAtmColorMult; // C72380KD - Reduced atmColorMult impact on some things
            #endif

            vec3 colorSample = mix(cloudAmbientColor * (0.3 * sunVisibility2 + 0.5),
                                   cloudLightColor * (0.85 + 1.15 * scattering),
                                   sampleLighting);
            colorSample *= 1.0 - 0.4 * rainStrength;
            colorSample *= CLOUD_CYV_BRIGHTNESS;
            colorSample *= 1.0 - 0.2 * (1.0 - skyFadeM) * max(sunVisibility2, nightFactor);
            colorSample = mix(cloudSkyColor, colorSample, cloudFogFactor * 0.69);
            colorSample *= pow2(1.0 - maxBlindnessDarkness);

            volumetricClouds.rgb = mix(volumetricClouds.rgb, colorSample, 1.0 - min1(volumetricClouds.a));
            volumetricClouds.a += opacityFactor * pow(cloudDistanceFactor, 0.5 + 10.0 * pow(abs(VdotSM1M), 90.0)) * cloudMult;
        }

        samplePos += sampleStep;
        sampleTotalLength += sampleLength;
    }

    if (volumetricClouds.a > 0.5) cloudLinearDepth = sqrt(firstHitPos / renderDistance);

    volumetricClouds.a *= 0.5 + 0.5 * skyFadeM;
    volumetricClouds.a *= CLOUD_CYV_OPACITY;

    return volumetricClouds;
}
