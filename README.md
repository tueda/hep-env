# hep-env

## Usage

```bash
docker pull ghcr.io/tueda/hep-env:main
[ -d models ] || docker run --rm -v "$(pwd):/work" ghcr.io/tueda/hep-env:main cp -r /opt/MG5_aMC/models .
docker run -it --rm -v "$(pwd):/work" -v "$(pwd)/models:/opt/MG5_aMC/models" ghcr.io/tueda/hep-env:main
```

```bash
[ -d models ] || apptainer exec docker://ghcr.io/tueda/hep-env:main cp -r /opt/MG5_aMC/models .
apptainer shell --bind "$(pwd)/models:/opt/MG5_aMC/models" docker://ghcr.io/tueda/hep-env:main
```

## Development

```bash
docker build --progress=plain -t hep-env .
[ -d models ] || docker run --rm -v "$(pwd):/work" hep-env cp -r /opt/MG5_aMC/models .
docker run -it --rm -v "$(pwd):/work" -v "$(pwd)/models:/opt/MG5_aMC/models" hep-env
```

```bash
docker build --progress=plain -t hep-env .
[ -d models ] || apptainer exec docker-daemon:hep-env:latest cp -r /opt/MG5_aMC/models .
apptainer shell --bind "$(pwd)/models:/opt/MG5_aMC/models" docker-daemon:hep-env:latest
```
