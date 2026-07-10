# hep-env

## Usage

### Docker

```bash
docker pull ghcr.io/tueda/hep-env:latest
[ -d data ] || docker run --rm -v "$(pwd):/work" ghcr.io/tueda/hep-env:latest cp -r /data .
docker run -it --rm -v "$(pwd):/work" -v "$(pwd)/data:/data" ghcr.io/tueda/hep-env:latest
```

### Apptainer

```bash
[ -d data ] || apptainer exec docker://ghcr.io/tueda/hep-env:latest cp -r /data .
apptainer shell --bind "$(pwd)/data:/data" docker://ghcr.io/tueda/hep-env:latest
```

## Development

```bash
pre-commit install
pre-commit run --all-files
make run-docker
make run-apptainer
```
