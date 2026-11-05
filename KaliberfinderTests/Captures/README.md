# Training captures

Packages recorded with Kaliberfinder's hidden training capture screen: tap the copyright line on
the home screen five times, then «Trainingsdaten aufnehmen». Pick the calibre, take the photos and
share the series as a ZIP. Unzip it here (one folder per series) and commit it;
`CaptureFixtureTests` runs every shot through the photo analysis and reports `CAPTURE` lines in
the CI log.

```
<calibre>-<yyyyMMdd-HHmmss>/
  package.json            calibre (catalogue id), part (cartridge | emptyCase), note, device, iOS, app version
  01/
    shot.json             source, EXIF orientation, depth map size and accuracy, camera calibration,
                          LiDAR table distance and focal length, gravity and tilt, the app's analysis then
    photo.heic | .jpg     the photo exactly as delivered (EXIF kept)
    depth.f32             LiDAR depth, Float32 little-endian, metres, row by row (photo's stored pixel frame)
    vision-instances.png  Vision foreground instances, 8-bit label per pixel, 0 = background (upright photo, 1600 px)
  02/ …
```

Depth and calibration are in the frame of the photo's stored pixels (before the EXIF rotation);
the Vision mask is in the upright frame. Only the LiDAR camera records depth; photos added from
the library have no depth, but are still useful for the shape.

Keep the photos reasonably small: a HEIC from the camera is about 2–4 MB.
