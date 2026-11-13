# Design references

PawDoodle's engine was developed with the following public material as design references. This repository contains PawDoodle's implementation and a generated noise lattice.

- [Google Ink Stroke Modeler](https://google.github.io/ink-stroke-modeler/) for causal input modeling, prediction, and the stable/mutable stroke split.
- [AndroidX Ink brush API](https://developer.android.com/reference/androidx/ink/brush/package-summary) for brush family, tip, behavior, and paint as separate concepts.
- [libmypaint](https://github.com/mypaint/libmypaint) for data-driven brush settings, filtered brush direction, and the relationship between dab overlap and opacity.
- [Krita brush engines](https://docs.krita.org/en/reference_manual/brushes/brush_engines.html) for independent bristle trails, paper texture, and material accumulation.
- [Procreate Brush Studio](https://help.procreate.com/procreate/handbook/brushes/brush-studio-settings) and [Clip Studio Paint](https://help.clip-studio.com/en-us/manual_en/240_brushes/Customizing_brush_tools.htm) for independently authored spacing, grain, taper, tip shape, and input dynamics.
- [Apple PencilKit](https://developer.apple.com/documentation/pencilkit) for the drawing interaction and support for distinct ink types.
- [Curtis et al., Computer-Generated Watercolor](https://grail.cs.washington.edu/projects/watercolor/) for the roles of fluid, pigment deposition, capillary effects, and paper granulation.
- [p5.brush](https://github.com/acamposuribe/p5.brush) for separation of tip, grain, spacing, pressure, and natural-media controls.
