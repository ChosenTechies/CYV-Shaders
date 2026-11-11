// CYV-style fog
// Custom fog model for the CYV pipeline, using the pack's own color
// variables and fog application interface.

vec3 GetCYVFogColor(vec3 nViewPos, float lViewPosRaw, float VdotU, float VoL) {
    float lViewPos = 1.0 - exp(-pow2(lViewPosRaw / 64.0));

    float density = 0.4;
    float nightDensity = 1.0;
    float weatherDensity = 1.5;

    float sunSkyVis = sunVisibility2 * invRainFactor;

    float exposure = exp2(noonFactor * 0.75 - 0.75);
    float nightExposure = exp2(-3.5);
    float weatherExposure = 1.0;

    float baseGradient = exp(-(VdotU * 0.5 + 0.5) * 0.5 / density);

    vec3 fog = mix(nightMiddleSkyColor, dayMiddleSkyColor, sunFactor);
    fog *= baseGradient;
    fog = fog / sqrt(fog * fog + 1.0) * exposure * sunSkyVis;

    float sunMix = pow((VoL * 0.5 + 0.5) * clamp(1.0 - VdotU, 0.0, 1.0), 2.0 - sunSkyVis) *
                   pow(1.0 - noonFactor * 0.6, 3.0);
    float horizonMix = pow(1.0 - abs(VdotU), 2.5) * 0.125;
    float lightMix = (1.0 - (1.0 - sunMix) * (1.0 - horizonMix)) * lViewPos;

    vec3 lightFog = pow(lightColor * sunVisibility2, vec3(4.0 - sunSkyVis)) * baseGradient;
    lightFog = lightFog / (1.0 + lightFog * rainFactor);

    fog = mix(
        sqrt(fog * (1.0 - lightMix)),
        sqrt(lightFog),
        lightMix
    );
    fog *= fog;

    float nightGradient = exp(-(VdotU * 0.5 + 0.5) * 0.35 / nightDensity);
    vec3 nightFog = nightClearLightColor * nightClearLightColor * nightGradient * nightExposure;

    fog = mix(nightFog, fog, sunVisibility2);

    float rainGradient = exp(-(VdotU * 0.5 + 0.5) * 0.125 / weatherDensity);
    vec3 weatherColM = mix(nightMiddleSkyColor, dayMiddleSkyColor, sunFactor);
    vec3 weatherFog = weatherColM * weatherColM * weatherExposure;
    weatherFog *= GetLuminance(ambientColor / weatherFog) * (0.2 * sunSkyVis + 0.2);
    fog = mix(fog, weatherFog * rainGradient, rainFactor);

    float exteriorFactor = eyeBrightnessM;

    fog = mix(nightClearAmbientColor * 0.5, fog * exteriorFactor, exteriorFactor);

    return fog;
}

void DoCYVFog(inout vec4 color, vec3 playerPos, float lViewPos, float VdotS, float dither) {
    vec3 nPlayerPos = normalize(playerPos);
    float VdotU = dot(nPlayerPos, upVec);

    vec3 lightVec = sunVec * ((timeAngle < 0.5325 || timeAngle > 0.9675) ? 1.0 : -1.0);
    float VoL = dot(nPlayerPos, lightVec);

    float fog = lViewPos * CYV_FOG_DENSITY / 1024.0;
    float clearDay = sunVisibility2 * invRainFactor * (1.0 - rainFactor);

    #if defined DISTANT_HORIZONS || defined VOXY
        fog *= CYV_FOG_DENSITY_LOD;
    #endif

    float exteriorFactor = eyeBrightnessM;

    float fogDensityMult = mix(1.0, CYV_FOG_DENSITY_WEATHER, rainFactor) / mix(1.0 / CYV_FOG_DENSITY_NIGHT, 1.0, clearDay);
    fogDensityMult = mix(CYV_FOG_DENSITY_INDOOR, fogDensityMult * exteriorFactor, exteriorFactor);

    fog *= fogDensityMult;
    float fogDampen = 0.3 * rainFactor + 0.5;
    fog = min(fog, (fog - fogDampen) * 0.25 + fogDampen);

    #ifdef CYV_FOG_HEIGHT
        fog *= exp2(-max0(playerPos.y + cameraPosition.y - CYV_FOG_HEIGHT_Y) / exp2(CYV_FOG_HEIGHT_FALLOFF));
    #endif

    fog = 1.0 - exp(-2.0 * pow(fog, 0.35 * clearDay * exteriorFactor + 1.25));

    vec3 fogColorM = GetCYVFogColor(nPlayerPos, lViewPos, VdotU, VoL);

    #ifdef ATM_COLOR_MULTS
        fogColorM *= atmColorMult;
    #endif
    #ifdef MOON_PHASE_INF_ATMOSPHERE
        fogColorM *= moonPhaseInfluence;
    #endif

    color = mix(color, vec4(fogColorM, 0.0), clamp(fog, 0.0, 1.0));
}
