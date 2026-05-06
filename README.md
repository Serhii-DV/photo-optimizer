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
