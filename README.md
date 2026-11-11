# CYV Shader

A feature-rich shaderpack for **Iris**, made by **Chosentechies**. It ships
two looks for every major visual system — atmosphere, clouds, water surface,
color grading — so you can switch styles freely in the Shader Options menu
without losing anything.

## Highlights

| Feature | Where to find it |
|---|---|
| Volumetric slab clouds (three base shapes, density, coverage, thickness, stretch...) | `Sky & Weather > Clouds` |
| Heightmap-based water caustics with a strength slider | `Materials & Water > Water` |
| Two tonemapping curves (exposure, curve shaping, white path) | `Effects > Color Balance` |
| Height-based atmospheric fog with day/night/weather/indoor density (Overworld) | `Sky & Weather > Fog` + `CYV Fog Settings` |
| Dirty Lens (bloom-illuminated smudges) | `Effects > CYV Extras` (requires Bloom) |
| Retro Filter (color quantization + dithering) | `Effects > CYV Extras` |

The bundled **CYV Look** profile switches the whole pack to the alternative
look in one click.

Other core features: TAA, colored lighting, light shafts, improved rain,
Distant Horizons & Voxy support, dimension-specific atmospheres (Nether, End).

Shader options are available in **English and Estonian** (the Estonian texts
are used when the game language is set to `et_ee`; anything untranslated
falls back to English).

## Codebase layout

```
shaders/
├── cyv/                 core library ("the CYV lib")
│   ├── cyv.glsl           settings + defines hub
│   ├── uniforms.glsl       uniform declarations
│   ├── pipeline.glsl       pipeline setup
│   ├── util/               math + utility functions
│   ├── palette/            color definitions (sky, light, ambient...)
│   ├── atmosphere/         fog, clouds, sky, stars
│   ├── surfaces/           material handling
│   ├── shading/            lighting code
│   ├── floodlight/         voxel light propagation
│   ├── effects/            misc effects
│   ├── antialias/          FXAA/TAA
│   ├── overlaytext/        text rendering
│   └── textures/           custom textures
├── passes/               shader programs
└── world* / lang / *.properties
```

## Install

1. Put `CYV-Shaders.zip` (or the `CYV-Shaders` folder) in
   `.minecraft/shaderpacks/`.
2. Select it in Options > Video Settings > Shader Packs (Iris).
3. Recommended: Iris 1.7+ (the pack targets Iris 1.11.x).

## Credits

CYV Shader is made by **Chosentechies**.

## License

See `License.txt`. In short: free to use, edit and share with credit and this
license kept intact. No warranty.
