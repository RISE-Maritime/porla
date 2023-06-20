# porla
**P**ipeline-**O**riented **R**eal-time **L**ogging **A**ssistant or simply a basic toolbox for handling of line-based streaming data using linux pipes and some handy command-line utilities

> "porla" is also a Swedish word for the soothing sound of running water from a small stream of water

## Motivation and purpose

TODO

## Schematic overview

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

* **to_bus** and **from_bus**

  Pipes data to or from the `bus`, Expects a single argument, the `bus_id`.

* **record**

  Records (appends) data from STDIN to a file. Expects a single argument, the `file_path`.

* **branch**

  Branch the pipe at this place. Takes any number of arguments and execute those in the newly created branch.

* **b64**

  Base64 encodes (`--encode`) or decodes (`--decode`) data from STDIN to STDOUT.

* **jsonify**

  TODO

* **timestamp**

  Prepends a timestamp  to each line. The timestamp is either the unix epoch (`--epoch`) or in rfc3339 format (`--rfc3339`)

* **udp_listen**

  WIP

### Examples

```yaml
version: '3.8'

services:
    source_1:
        image: ghcr.io/mo-rise/porla
        network_mode: host
        restart: always
        command: ["socat UDP4-RECV:1457,reuseaddr STDOUT | timestamp | to_bus 1"]

    source_2:
        image: ghcr.io/mo-rise/porla
        network_mode: host
        restart: always
        command: ["mqtt subscribe -t my/topic/# | timestamp | to_bus 2"]

    transform_1:
        image: ghcr.io/mo-rise/porla
        network_mode: host
        restart: always
        command: ["from_bus 1 | jsonify '{} {name} {value}' | to_bus 3"]

    transform_2:
        image: ghcr.io/mo-rise/porla
        network_mode: host
        restart: always
        command: ["from_bus 2 | b64 --encode | to_bus 4"]

    sink_1:
        image: ghcr.io/mo-rise/porla
        network_mode: host
        restart: always
        command: ["from_bus 3 | mqtt publish -t another/topic"]

    sink_2:
        image: ghcr.io/mo-rise/porla
        network_mode: host
        restart: always
        command: ["from_bus 3 | socat STDIN UDP4-DATAGRAM:1458"]

    record_1:
        image: ghcr.io/mo-rise/porla
        network_mode: host
        restart: always
        volumes:
            - ./recordings:/recordings
        command: ["from_bus 1 | record /recordings/bus_id_1.log"]

    record_2:
        image: ghcr.io/mo-rise/porla
        network_mode: host
        restart: always
        volumes:
            - ./recordings:/recordings
        command: ["from_bus 2 | record /recordings/bus_id_2.log"]

    record_3:
        image: ghcr.io/mo-rise/porla
        network_mode: host
        restart: always
        volumes:
            - ./recordings:/recordings
        command: ["from_bus 3 | record /recordings/bus_id_3.log"]

    record_4:
        image: ghcr.io/mo-rise/porla
        network_mode: host
        restart: always
        volumes:
            - ./recordings:/recordings
        command: ["from_bus 4 | record /recordings/bus_id_4.log"]
```