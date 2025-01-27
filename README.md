# README

## Overview

As this interacts with my personal media collection, I've tried to be particularly
careful to not make any destructive changes to the data hence there a few
precautions in place.

## Containers

### dovi_tool

#### Overview

This is a container that I use to run [dovi_tool](https://github.com/quietvoid/dovi_tool)
to convert the Dolby Vision metadata in my media collection to a format that
Infuse can understand.

#### Tools Used

- dovi_tool
- ffmpeg
- mediainfo
- jq
- mkvtoolnix
- mkvmerge

Everything is handled from the [`entrypoint.sh`](./dovi_tool/entrypoint.sh) script.

#### Usage

> **Warning**: This will overwrite the original file if the target profile is found.

```bash
#docker run --rm -it -v /path/to/media:/opt/media -e PROFILE=dvhe.07 ghcr.io/olsson/dovi_tool:latest 

$ docker run --rm -it -v /path/to/media:/opt/media -e PROFILE=dvhe.07 ghcr.io/olsson/dovi_tool:latest
```

#### Changes to make this easier to use 

This fork contains changes to allow the Docker container scan the specified folder for MKV files, 
and to be able to start the script from the Unraid GUI without needing to open the command line.
