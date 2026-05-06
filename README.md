# photo-optimizer

Bash scripts that converts and optimizes photos and videos

## Usage

Optimize supported photos and videos from one folder:

```bash
./optimize.sh --input /path/to/media
```

By default, optimized files are saved to `/path/to/media/optimized`.

Optional settings:

```bash
./optimize.sh --input /path/to/media --output /path/to/output --photo-quality 80 --video-crf 32
```
