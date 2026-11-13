#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec4 uBounds;
uniform vec2 uPixels;
uniform vec4 uMaterial; // wet, paper scale, grain strength, optical density
uniform vec4 uWet; // dilution, bleed, diffusion, granulation
uniform vec4 uLoad; // opacity, residue, seed, detail
uniform vec3 uPaper; // paper rotation, fine scale, contact coverage gain
uniform vec3 uPigment;
uniform vec3 uDrag; // strength, length, width in document units
uniform sampler2D uContact;
uniform sampler2D uNoise;
out vec4 fragColor;

float noise(vec2 p) {
  vec2 cell = floor(p), f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  // One filtered lookup replaces four floating hashes. The 512-cell noise
  // lattice has a wrapping gutter; the differently scaled world fields do
  // not repeat a finished brush texture at the old 54.4px interval.
  return texture(uNoise, (mod(cell, 512.0) + f + 1.5) / 514.0).r;
}
vec4 contact(vec2 p) {
  return texture(uContact, clamp((p - uBounds.xy) / uBounds.zw,
                                .5 / uPixels, 1.0 - .5 / uPixels));
}
vec4 materialAt(vec2 p) {
  vec4 mask = contact(p);
  // Dry material cannot deposit beyond the contact. Reject transparent
  // pixels before evaluating the paper and directional drag fields.
  if (uLoad.x < .0001 || (uMaterial.x < .5 && mask.a < .0001)) {
    return vec4(0);
  }
  float c = cos(uPaper.x), s = sin(uPaper.x);
  vec2 paper = vec2(p.x * c - p.y * s, p.x * s + p.y * c)
      / max(.12, uMaterial.y) + vec2(uLoad.z * .71, uLoad.z * .37);
  vec2 warp = vec2(noise(paper / 9.3), noise(paper / 11.7 + 71.0)) - .5;
  vec2 tooth = paper + warp * 2.3;
  float fine = noise(tooth / ((.22 + .42 * (1.0 - uLoad.w)) * max(.15, uPaper.y)));
  bool wet = uMaterial.x > .5;
  float flake = noise(tooth / (wet ? 1.18 : 1.3) + 17.0);
  float fiber = noise((paper + warp * 3.0)
      / (wet ? vec2(1.25, 1.9) : vec2(.55, 2.1)) + 193.0);
  float pool = noise(paper / (wet ? 13.0 : 11.0) + warp * .8);
  if (wet) {
    vec2 turned = vec2(paper.x * .8 - paper.y * .6,
                       paper.x * .6 + paper.y * .8);
    pool = .55 * pool + .30 * noise(turned / 6.5 + 41.0)
                     + .15 * noise(turned / 3.1 + 137.0);
  }
  float bloom = noise(paper / (wet ? 3.3 : 4.0) + warp * 1.6 + 29.0);
  float water = mask.a;
  if (wet) {
    // Move the contact boundary through a stationary capillary field. Water
    // support uses maximum reach; pigment uses a conservative local average.
    // Keeping those responses separate avoids a textured circular alpha mask.
    float age = mask.a > .0001 ? clamp(mask.b / mask.a, 0.0, 1.0) : 1.0;
    vec2 capillary = vec2(noise(paper / 1.1 + 57.0), noise(paper / 1.7 + 113.0)) - .5;
    vec2 wetPoint = p + capillary * uWet.z * (1.0 + uWet.y) * (.25 + .75 * age);
    mask = contact(wetPoint);
    water = mask.a;
    float spreadPigment = 0.0;
    float reach = uWet.z * (.6 + 1.8 * fiber);
    for (int i = 0; i < 8; i++) {
      float angle = float(i) * .7853981634;
      vec4 q = contact(wetPoint + vec2(cos(angle), sin(angle)) * reach);
      float absorbed = q.a > .0001 ? clamp(q.b / q.a, 0.0, 1.0) : 0.0;
      float transported = q.a * (.2 + .8 * absorbed);
      water = max(water, transported * (.55 + .35 * fiber));
      spreadPigment += transported * .125;
    }
    mask.a = mix(mask.a, spreadPigment, uWet.y * .42);
  }
  if (max(mask.a, water) < .0001 || uLoad.x < .0001) {
    return vec4(0);
  }
  float load = clamp(mask.a / max(.001, uLoad.x), 0.0, 1.0);
  float alpha;
  if (uMaterial.x < .5) {
    // Dry contact stores an unoriented drag axis. Reversing along a stroke
    // must not cancel the direction and abruptly rotate the paper streaks.
    vec2 axis = mask.rg / max(.0001, mask.a) * 2.0 - 1.0;
    float angle = dot(axis, axis) > .00001 ? .5 * atan(axis.y, axis.x) : 0.0;
    vec2 direction = vec2(cos(angle), sin(angle));
    direction = vec2(direction.x*c-direction.y*s, direction.x*s+direction.y*c);
    float rub = .5;
    if (uDrag.x > .001) {
      rub = 0.0;
      for (int i = 0; i < 9; i++) {
        vec2 dragged = paper + direction * (float(i) - 4.0) *
            uDrag.y / (8.0 * max(.12, uMaterial.y));
        rub += noise(dragged / max(.2, uDrag.z / max(.12, uMaterial.y)) + 271.0) / 9.0;
      }
      rub = smoothstep(.40, .60, rub);
    }
    float height = .45 * flake + .25 * fine + .14 * fiber + .16 * bloom;
    height += uDrag.x * .26 * (.5 - rub);
    height = mix(.5, height, clamp(uMaterial.z + uLoad.w, 0.0, 1.0));
    // Thin wax can still catch the highest paper fibers. Occupied area grows
    // before optical thickness; one threshold for both made a binary band.
    float pressure = .20 + sqrt(load) * .56
        - uMaterial.z * (.12 * (bloom - .5) + .18 * (pool - .5));
    float toothContact = smoothstep(height - .16, height + .16, pressure);
    // Optical response follows paper contact. Applying it to the geometric
    // ribbon first sealed its pores and saturated the entire core.
    float deposited = 1.0 - pow(1.0 - toothContact, uPaper.z);
    float opticalMass = load * (.25 + .75 * load) *
        (1.0 - uDrag.x * .45 * (1.0 - rub));
    opticalMass *= 1.0 + .24 * uDrag.x * smoothstep(.55, .90, rub);
    float opaqueWax = toothContact *
        (1.0 - exp(-uMaterial.w * deposited * opticalMass * uPaper.z));
    // Rubbing carries a thin film over the valleys between opaque wax flakes.
    // Keep its directional streaks distinct from the stationary paper tooth.
    float rubbedFilm = uDrag.x * uLoad.y * load * (.55 + .45 * rub);
    // A little extra wax bridges the strongest directional drags. This deepens
    // smeared marks in the paper valleys instead of only saturating flakes.
    rubbedFilm += .14 * uDrag.x * uLoad.y * load * smoothstep(.55, .90, rub);
    float residue = max(rubbedFilm,
        uLoad.y * load * toothContact * (1.0 - toothContact));
    // A thin wax binder remains between tooth contacts. Its authored residue
    // controls this film; pores retain their stationary fine-scale structure.
    residue = 1.0 - (1.0 - residue) * (1.0 - uLoad.y * .48 * load);
    residue = 1.0 - (1.0 - residue) * (1.0 - uLoad.y * .30 * load *
        (1.0 - smoothstep(.10, .45, toothContact)));
    alpha = uLoad.x * (residue + (1.0 - residue) * opaqueWax);
  } else {
    float waterLoad = clamp(water / max(.001, uLoad.x), 0.0, 1.0);
    float paperFront = mix(flake, fiber, .6);
    float wetFront = smoothstep(.035 + .06 * paperFront,
                                .10 + .09 * paperFront, waterLoad);
    float mass = .80 + uMaterial.z * 1.05 * (pool - .5) + .14 * (bloom - .5)
                + uWet.w * .65 * (fiber - .5) + uLoad.w * .75 * (fine - .5);
    mass *= (1.0 - uWet.x * .5);
    float wash = 1.0 - exp(-mass * (.12 + load * 1.2));
    alpha = uLoad.x * wetFront * wash;
  }
  alpha = clamp(alpha, 0.0, uLoad.x);
  return vec4(uPigment * alpha, alpha);
}

vec4 documentTexel(vec2 p) {
  // Match the RGBA8 document raster before interpolation, without forcing a
  // GPU -> CPU image snapshot for the material pass on CanvasKit.
  return floor(materialAt(p) * 255.0 + .5) / 255.0;
}

void main() {
  // Reconstruct the authored 2x document grid at every viewport scale. Direct
  // continuous evaluation would change the grain on zoom or commit. This is
  // the same bilinear reconstruction as a canonical RGBA8 material image.
  vec2 pixel = FlutterFragCoord().xy * 2.0 - .5;
  vec2 cell = floor(pixel), f = fract(pixel);
  vec2 origin = (cell + .5) * .5;
  vec4 a = documentTexel(origin);
  if (max(f.x, f.y) < .0001) {
    fragColor = a;
    return;
  }
  vec4 b = documentTexel(origin + vec2(.5, 0));
  vec4 c = documentTexel(origin + vec2(0, .5));
  vec4 d = documentTexel(origin + vec2(.5, .5));
  fragColor = mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
