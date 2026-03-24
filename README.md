# hep-env

## Usage

```bash
docker pull ghcr.io/tueda/hep-env:main
[ -d data ] || docker run --rm -v "$(pwd):/work" ghcr.io/tueda/hep-env:main cp -r /data .
docker run -it --rm -v "$(pwd):/work" -v "$(pwd)/data:/data" ghcr.io/tueda/hep-env:main
```

```bash
[ -d data ] || apptainer exec docker://ghcr.io/tueda/hep-env:main cp -r /data .
apptainer shell --bind "$(pwd)/data:/data" docker://ghcr.io/tueda/hep-env:main
```

## Development

```bash
docker build --progress=plain -t hep-env .
[ -d data ] || docker run --rm -v "$(pwd):/work" hep-env cp -r /data .
docker run -it --rm -v "$(pwd):/work" -v "$(pwd)/data:/data" hep-env
```

```bash
docker build --progress=plain -t hep-env .
[ -d data ] || apptainer exec docker-daemon:hep-env:latest cp -r /data .
apptainer shell --bind "$(pwd)/data:/data" docker-daemon:hep-env:latest
```
