# porla
**P**ipeline-**O**riented **R**eal-time **L**ogging **A**ssistant or simply a basic toolbox for handling of line-based streaming data using linux pipes and some handy command-line utilities

    "porla" is also a Swedish word for the soothing sound of running water from a small stream stream, typically set in an enchanted forest.

## Motivation, purpose and mental map


![schematic](./porla.svg)

## Usage

It is packaged as a docker image, available here: https://github.com/orgs/MO-RISE/packages

The image expects a "run" command inputted on startup. Using docker run, this would manifest as such:
```
docker run --network=host porla "<command>"
```

Using docker-compose it would look like this:
```
version: '3'
services:
    service_1:
        image: ghcr.io/mo-rise/porla
        network_mode: host
        restart: always
        command: ["<command>"]
```

### Built-in functionality

TODO

### Examples