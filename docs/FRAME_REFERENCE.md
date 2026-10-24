# Combat reference study — revision 9

The reference videos were downloaded for local visual study. The observations below describe visible poses and transitions, not extracted animation data. No downloaded reference video, decoded frame sheet or animation extracted from these videos is included in the game or repository. The existing user-provided character assets are preserved. The local study files remain in ignored `.runtime/reference-v9/`.

## Sources and method

| Source | Decoded video | Study |
| --- | --- | --- |
| Bandai Namco, [ER How-To: Attacks](https://www.youtube.com/watch?v=f_TyW4z4fkA) | 1280 × 720, 60 fps | Every decoded frame 18–97, plus the complete clip sampled every 0.1 s |
| Bandai Namco, [ER How-To: Heavy](https://www.youtube.com/watch?v=_R89o87YN1c) | 1280 × 720, 60 fps | Every decoded frame 156–195, plus the complete clip sampled every 0.2 s |
| Bandai Namco, [ER How-To: Movement Attacks](https://www.youtube.com/watch?v=oL2Qc8fQy3M) | 1280 × 720, 60 fps | Available supplementary source; not the basis for the frame ranges below |
| mike, [Maliketh solo, melee only](https://www.youtube.com/watch?v=8htSFZKzcS0) | Downloaded rendition: 1280 × 720, 60 fps | Every decoded frame in 116.000–116.650 s, plus 85–93, 116–124 and 146–154 s sampled every 0.4 s |
| Zombie Headz, [Longsword Moveset](https://www.youtube.com/watch?v=jyr3OsGlMR0) | Source metadata: 30 fps | Supplementary light/heavy contact sheets used to inspect the more visible side-view stance and foot placement |

The primary publisher also embeds the short official clips in its [combat guide](https://www.bandainamcoent.com/news/elden-ring-introduction-part-4-combat-guide).

Frame numbers are zero-based positions in the decoded video. At 60 fps, frame 18 is 0.300 s. They are **not engine simulation frames**. Compression, camera motion, grass, armour and effects obscure some joints. These images cannot establish exact damage windows, input buffering, invulnerability frames, force, or the numerical phase lag between pelvis and chest. The choreography decisions below are an interpretation of visible motion.

## Knight: linked cuts

In the official light-attack clip:

| Decoded frames | Visible landmark | Consequence for our choreography |
| --- | --- | --- |
| 18–22, 0.300–0.367 s | Ready pose before the first visible preparation | Keep a readable preparation before a standalone attack |
| 23–27, 0.383–0.450 s | Sword rises across the shoulder; torso rotates into the preparation | Load the body and shoulder with the sword rather than moving only the forearm |
| 28–34, 0.467–0.567 s | Blade crosses the front of the body, torso turns and the stance compresses | Couple the cut to body rotation and weight transfer |
| 35–43, 0.583–0.717 s | Blade travels low to the opposite side while the torso continues to settle | Preserve the outgoing pose and its side of the body |
| 44–51, 0.733–0.850 s | Weapon and chest gather for the return; no full return to the starting ready pose | Begin the next linked attack from the actual preceding pose |
| 52–62, 0.867–1.033 s | Return cut crosses the body and finishes lower | Reverse the body action with a separate visible arc |
| 63–84, 1.050–1.400 s | Low follow-through remains visible as the posture settles | Brake the strike through the legs and torso; avoid an immediate upright reset |
| 85–97, 1.417–1.617 s | Gradual recovery continues from the lowered weapon | Recovery should be continuous, including when input does not continue the chain |

The wider contact sheets show a later forward extension around 2.6–2.8 s and a higher preparation/downward finish around 3.7–4.0 s. These support distinct thrust and descending-cut silhouettes rather than repeating the first sweep with different speed.

In the supplementary longsword side view, the forward strike uses a bent front knee, a trailing leg and an advancing torso. The trailing foot then catches the body. Foot positions must therefore account for actual controller travel: pinning both feet to the initial world positions through a moving attack creates an overextended rear leg and is not supported by the reference.

## Knight: heavy commitment

The official heavy clip's decoded frames 156–195 (2.600–3.250 s) show the weapon gathering near shoulder level, a body turn through the strike, and a lower extended end pose. The wider clip includes a separate, longer held preparation around 10.6–11.2 s followed by a clear release. A charged attack should therefore keep a loaded posture during the hold and release through the body; it should not repeatedly restart its wind-up.

The supplementary longsword heavy side view shows a forward step with a deep bent lead knee and a trailing foot. The body remains inclined during extension and only then unwinds. This is useful for the step and recovery shapes, while our own attack timings and balance remain authoritative.

## Beast: low support, landing and movement

In the 116.000–116.650 s adjacent-frame sequence:

| Relative decoded frames | Visible landmark | Consequence for our choreography |
| --- | --- | --- |
| 0–9 | Body crosses laterally while the weapon trails; the silhouette is extended | Move the root and limbs together; do not fake repositioning by swinging the chest in place |
| 10–19 | Body lowers toward the ground and the front support reaches down | Land through the supporting limbs with a low torso |
| 20–29 | Body remains compressed and the sword stays near the floor | Keep crouched support after landing instead of snapping upright |
| 30–39 | Crouched posture settles and turns back toward the player | Separate landing absorption from the next attack's preparation |

The 116–124 s overview shows low approaches, turns and close attacks joined without a long upright ready pose. The 146–154 s overview includes a forward approach, a low sword drag around 148.4–148.8 s, and a later rise/turn into another attack. The 85–93 s overview shows large airborne strings, but those are a stronger mobility reference than the short ground bounds needed for our encounter.

The resulting design target is a few short, readable changes of position with preload, a brief unloaded phase, a low landing and a turn toward the player. This is an authored adaptation, not a copy of Maliketh's complete moveset. Recovery from a missed heavy attack must remain punishable; repositioning should start after that recovery and should not add damage or invulnerability by itself.

## Reproducible local extraction

The adjacent-frame sheets were generated with FFmpeg without an `fps` filter. Example for the first 40 light-attack frames:

```sh
ffmpeg -i .runtime/reference-v9/official-light.webm \
  -vf "select='between(n,18,57)',setpts=PTS-STARTPTS,scale=320:180,tile=5x8" \
  -frames:v 1 .runtime/reference-v9/official-light-everyframe-018-057.jpg
```

The second light sheet selects 58–97; the heavy sheet selects 156–195. The beast sheet seeks to 116 s and keeps the next 40 decoded frames. The study inspected 160 adjacent frames in these targeted passages, in addition to the broader sampled overviews. This number describes the inspected video frames, not a claim of reconstructed game animation or exact timing parity.
