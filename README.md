# photo-optimizer

Bash scripts that converts and optimizes photos and videos

## Usage

Optimize supported photos and videos from one folder:

```bash
./optimize.sh --input /path/to/media
```

Optimize one media file:

```bash
./optimize.sh --input /path/to/media/photo.jpg
./optimize.sh --input /path/to/media/video.mp4
```

By default, optimized files are saved to an `optimized` folder beside the input.

Optional settings:

```bash
./optimize.sh --input /path/to/media --output /path/to/output --photo-quality 80 --video-crf 32
```

By default, existing optimized files are kept so an interrupted folder run can continue:

```bash
./optimize.sh --input /path/to/media --existing keep
```

Rewrite already optimized files:

```bash
./optimize.sh --input /path/to/media --existing rewrite
```

Verify EXIF data in one image or a folder:

```bash
./verify_exif.sh --input /path/to/media
./verify_exif.sh --input /path/to/media/photo.webp
```

## Shell alias

Install a user-level Bash alias in `~/.bash_aliases`:

```bash
make install-alias
source ~/.bash_aliases
```

The default alias is `optimize-media`:

```bash
optimize-media --input /path/to/media
```

Use a custom alias name:

```bash
make install-alias ALIAS_NAME=optimize-photos
```
