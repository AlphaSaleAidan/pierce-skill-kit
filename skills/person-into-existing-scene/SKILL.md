---
name: person-into-existing-scene
description: Use when a consenting person must replace the lead performer in footage you own or have licensed (a re-cast commercial, a personalised version of your own spot, a re-shoot you can't schedule) — keeping the edit's cut, grade and music — or when local face swaps (inswapper, hyperswap, FaceFusion) look fake. Requires the inserted person's written consent and rights to the footage.
---

# Person into an existing scene

## Overview
Don't swap a face onto the footage. **Generate the person in-scene** (identity-edit of their REAL photos →
image-to-video), then **composite that clip over the edit's own plates** with only the original performer
removed. The edit's cut, grade, softness and grain stay the edit's; only the person changes.

## Consent, rights and honest use (hard rules)
- **Written consent from the person being inserted**, scoped to this project and its distribution, before
  any generation. Same for their voice if it's used. No consent, no job.
- **Rights to the footage.** Use only footage you own, commissioned, or licensed for this kind of
  modification (check the original performer's contract too). Not for film/TV clips, other people's
  social posts or anything you merely downloaded.
- If a generation service refuses the footage as copyrighted (`ip_detected` or similar): **stop.** That is
  a rights question. Never crop, flip, blur, re-grade or re-trim footage to get it past the check.
- **No deception.** Never use the result to make someone appear to do or say something they didn't agree
  to, to impersonate, for fraud, or for political/news content. Label it as edited/synthetic wherever the
  platform or law requires it.
- Other performers in the scene keep their real faces and voices. Never clone a non-consenting person's
  voice; if their line has to change, fix it on screen (subtitle) instead.

## When to use / not
- Use: replacing the lead in your own spot, personalised versions of a commercial you own, re-casting a
  performer who has left with a new consenting one.
- Green-screen talent into a generated set → `greenscreen-to-ai-plate-comp`.
- Rebuilding the edit itself from clean sources (music sync, cadence, grade) → `edit-rebuild-from-clean-sources`.

## Pipeline
1. **Clean sources.** The master or highest-quality export of the edit and its clean music/dialogue stems.
   Never rebuild from a compressed social upload with mixed audio.
2. **Shot map.** Per shot: keep / generate-and-comp / full-frame. Plain dark backgrounds → full-frame;
   anything with crew, set or props in front → comp over the plate.
3. **Identity stills** (`higgsfield-production-routing`, or any identity-preserving image edit): edit a real
   photo of the person — "same person, same face; add <role's wardrobe/hair>; <scene lighting>; framing
   matching this reference frame". Use OPEN-EYED references (smiling selfies make the result squint).
   Reject any still where identity drifted; compare side by side with the photo.
4. **Image → video** from the approved still. For a speaking shot pass the (consented) voice as an audio
   reference so the model lip-syncs.
5. **Pick the window**: gaze and head angle must match the original performer (`lip-sync-and-gaze-qc`).
   Measure mouth-vs-voice lag on speaking shots (generated mouths often run several frames ahead).
6. **Composite** (`scripts/composite_person.py`): performer-only mask (person segmentation ∩ a column
   around their face, so bystanders stay) → LaMa inpaint → fit by face height + eye centre → RVM matte →
   LAB grade to the performer's region → blur until Laplacian variance matches the plate → matched grain.
   `--fullframe` for plain shots, `--lag N` for measured lip lag (eases in, never freezes),
   `--clean-plate` when you have one.
7. **Gaze fix** if the clip side-eyes: FaceFusion `face_editor` (live_portrait) small horizontal gaze
   correction on a GPU machine (`remote-gpu-render`).
8. **Assemble + QC**: a fresh-context reviewer, frame by frame, at client zoom (`video-qc-reviewer`).

```bash
python scripts/composite_person.py --plates shot07.mp4 --gen gen/person_07.mp4 \
  --actor-face refs/original_performer.jpg --out comp/shot07 --gen-start 40 \
  --lama models/lama_fp32.onnx --rvm models/rvm_mobilenetv3_fp32.onnx
python scripts/composite_person.py --plates shot05.mp4 --gen gen/person_05.mp4 \
  --actor-face refs/original_performer.jpg --out comp/shot05 --fullframe ...
```
Models: LaMa ONNX (`lama_fp32.onnx`), RVM `rvm_mobilenetv3_fp32.onnx` (RobustVideoMatting releases),
insightface `buffalo_l`, rembg `u2net_human_seg`. Check each model's license before commercial use.

## Craft rules
- The role's signature look (wardrobe, hair, facial hair) goes in the identity-edit prompt, not in post.
- Eyeline goes where the original performer looked; never a side-eye.
- New generated inserts may extend the edit on the beat, graded to the edit's look.

## What FAILED
| Tried | Result | Do instead |
|---|---|---|
| inswapper_128 / hyperswap + GPEN face swap on the plates | Plastic skin, wrong bone structure, squint, facial hair lost | Identity-edit stills + image-to-video + comp |
| Generating the person from a text prompt / trained character | Face drifts from the real person | Edit REAL photos |
| Smiling/squinting selfies as identity refs | Squinting output | Rank refs by eye openness |
| Pasting the generated clip unsoftened | Much sharper than a compressed edit; reads as a sticker | Laplacian-matched blur + measured grain |
| Freezing frames to fix lip lag | Visible stall | Delay picture, ease in over ~1 s |

## Budget
Typical shot: one identity still + one 4 s clip. A 9-shot montage with one 7 s speaking shot runs to
hundreds of generation credits, roughly double with re-rolls. Quote first (`credit-discipline-for-generation`).

## Status
`composite_person.py` generalizes a job's working comp scripts but is **untested as generalized** (a smoke
run wrote 7 of 8 frames without errors; output not reviewed). Run it on 8–10 frames first and check a contact sheet.

Needs: written consent + footage rights; an identity-preserving image edit and image-to-video model (e.g. Higgsfield, paid); Python (opencv, numpy, onnxruntime, insightface, rembg, Pillow), ffmpeg; FaceFusion on a GPU for gaze fixes.
