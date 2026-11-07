# Training captures

Packages recorded with Kaliberfinder's hidden training capture screen: tap the copyright line in
«Einstellungen» five times, then «Trainingsdaten aufnehmen». Pick the calibre, take the photos and
share the series as a ZIP. New series go into the private training repo
(`ravench/kaliberfinder-training`, `tools/import_capture.py`), not here: this folder only keeps
the example package that `TrainingCaptureTests` reads. Shots picked as golden come back without
their photos in `../Golden` (see its README).

```
<calibre>-<yyyyMMdd-HHmmss>/
  package.json            calibre (catalogue id), part (cartridge | emptyCase), note, device, iOS, app version;
                          unlisted: true when calibre is the name of a round the catalogue lacks
  01/
    shot.json             source, EXIF orientation, depth map size and accuracy, camera calibration,
                          LiDAR table distance and focal length, gravity and tilt, closest focus
                          distance and lens position, the app's analysis then
    photo.heic | .jpg     the photo exactly as delivered (EXIF kept)
    depth.f32             LiDAR depth, Float32 little-endian, metres, row by row (photo's stored pixel frame)
    vision-instances.png  Vision foreground instances, 8-bit label per pixel, 0 = background (upright photo, 1600 px)
  02/ …
```

Depth and calibration are in the frame of the photo's stored pixels (before the EXIF rotation);
the Vision mask is in the upright frame. Only the LiDAR camera records depth; photos added from
the library have no depth, but are still useful for the shape.

Keep the photos reasonably small: a HEIC from the camera is about 2–4 MB.

A round the catalogue lacks (an old or unknown one) is recorded under «Nicht in der Liste» with a
name of its own: `calibre` is then that name and `unlisted` is true. The evaluation tool and the
scores leave such series out until the calibre is in the catalogue and the package gets its id.
