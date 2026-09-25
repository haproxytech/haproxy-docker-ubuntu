# Supported tags and respective `Dockerfile` links

-	[`3.5-dev7`, `s6-3.5-dev7`, `3.5`, `s6-3.5`](https://github.com/haproxytech/haproxy-docker-ubuntu/blob/main/3.5/Dockerfile)
-	[`3.4.5`, `s6-3.4.5`, `3.4`, `s6-3.4`, `latest`](https://github.com/haproxytech/haproxy-docker-ubuntu/blob/main/3.4/Dockerfile)
-	[`3.3.15`, `s6-3.3.15`, `3.3`, `s6-3.3`](https://github.com/haproxytech/haproxy-docker-ubuntu/blob/main/3.3/Dockerfile)
-	[`3.2.24`, `s6-3.2.24`, `3.2`, `s6-3.2`](https://github.com/haproxytech/haproxy-docker-ubuntu/blob/main/3.2/Dockerfile)
-	[`3.0.28`, `s6-3.0.28`, `3.0`, `s6-3.0`](https://github.com/haproxytech/haproxy-docker-ubuntu/blob/main/3.0/Dockerfile)
-	[`2.8.29`, `s6-2.8.29`, `2.8`, `s6-2.8`](https://github.com/haproxytech/haproxy-docker-ubuntu/blob/main/2.8/Dockerfile)
-	[`2.6.34`, `s6-2.6.34`, `2.6`, `s6-2.6`](https://github.com/haproxytech/haproxy-docker-ubuntu/blob/main/2.6/Dockerfile)

# Quick reference

- **Where to get help**:  
  [HAProxy mailing list](mailto:haproxy@formilux.org), [HAProxy Community Slack](https://slack.haproxy.org/) or [#haproxy on Libera.chat](irc://irc.libera.chat/%23haproxy)

- **Where to file issues**:  
  [https://github.com/haproxytech/haproxy-docker-ubuntu/issues](https://github.com/haproxytech/haproxy-docker-ubuntu/issues)

- **Maintained by**:  
  [HAProxy Technologies](https://github.com/haproxytech)

- **Supported architectures**: ([more info](https://github.com/docker-library/official-images#architectures-other-than-amd64))  
  `linux/amd64`, `linux/arm64`. `linux/arm/v7`

- **Image updates**:  
  [commits to `haproxytech/haproxy-docker-ubuntu`](https://github.com/haproxytech/haproxy-docker-ubuntu/commits/main), [top level `haproxytech/haproxy-docker-ubuntu` image folder](https://github.com/haproxytech/haproxy-docker-ubuntu)

- **Source of this description**:  
  [README.md](https://github.com/haproxytech/haproxy-docker-ubuntu/blob/main/README.md)

# What is HAProxy?

HAProxy is the fastest and most widely used open-source load balancer and application delivery controller. Written in C, it has a reputation for efficient use of both processor and memory. It can proxy at either layer 4 (TCP) or layer 7 (HTTP) and has additional features for inspecting, routing and modifying HTTP messages.

It comes bundled with a web UI, called the HAProxy Stats page, that you can use to monitor error rates, the volume of traffic and latency. Features can be toggled on by updating a single configuration file, which provides a syntax for defining routing rules, rate limiting, access controls, and more.

Other features include:

- SSL/TLS termination
- Gzip compression
- Health checking
- HTTP/2
- gRPC support
- Lua scripting
- DNS service discovery
- Automatic retries of failed connections
- Verbose logging

![logo](https://www.haproxy.org/img/HAProxyCommunityEdition_60px.png)

# How to use this image

This image is being shipped with a trivial sample configuration and for any real life use it should be configured according to the [extensive documentation](https://docs.haproxy.org/) and [examples](https://github.com/haproxy/haproxy/tree/master/examples). We will now show how to override shipped haproxy.cfg with one of your own.

## Create a `Dockerfile`

```dockerfile
FROM haproxytech/haproxy-ubuntu:3.0
COPY haproxy.cfg /usr/local/etc/haproxy/haproxy.cfg
```

## Build the container

```console
$ docker build -t my-haproxy .
```

## Test the configuration file

```console
$ docker run -it --rm my-haproxy haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg
```

## Run the container

```console
$ docker run -d --name my-running-haproxy my-haproxy
```

You will also need to publish the ports your HAProxy is listening on to the host by specifying the `-p` option, for example `-p 8080:80` to publish port 8080 from the container host to port 80 in the container.

## Use volume for configuration persistency

```console
$ docker run -d --name my-running-haproxy -v /path/to/etc/haproxy:/usr/local/etc/haproxy:ro haproxytech/haproxy-ubuntu:3.0
```

Note that your host's `/path/to/etc/haproxy` folder should be populated with a file named `haproxy.cfg` as well as any other accompanying files local to `/etc/haproxy`.

## Reloading config

To be able to reload HAProxy configuration, you can send `SIGUSR2` to the container:

```console
$ docker kill -s USR2 my-running-haproxy
```

## Enable Data Plane API

To use Data Plane API it is easiest to use s6-tagged images which all have Data Plane API running by default.

Despite the tag name, the s6-tagged images are no longer supervised by s6-overlay: they run [gopherd](https://github.com/haproxytech/gopherd) as PID 1, which starts HAProxy and Data Plane API and restarts either one if it exits. On first start a random password replaces the shipped `admin` placeholder in `/usr/local/etc/haproxy/dataplaneapi.yml`. HAProxy is started with two thirds of the container's memory limit (`-m`) and Data Plane API with one third (`GOMEMLIMIT`).

In these images `SIGUSR2` reloads HAProxy, and both `SIGTERM` and `SIGUSR1` stop the container. By default HAProxy then stops immediately. Set `USE_SIGUSR1` to any non-empty value to make it finish serving existing connections first. That lasts until `hard-stop-after` in your configuration expires, or without it until Docker's stop timeout, so raise that as well:

```console
$ docker run -d -e USE_SIGUSR1=1 --stop-timeout 60 haproxytech/haproxy-ubuntu:s6-3.4
```

The services can be managed from inside the container with `gopherd status`, `gopherd restart haproxy`, `gopherd signal haproxy USR2` and so on. For tooling and bind-mounted configuration written for the s6 images, `s6-svc` and `s6-svstat` are still present, including at their old `/command` and `/package/admin/s6/command` paths, and translate to gopherd: `s6-svc -2 /run/s6-rc/servicedirs/haproxy` still reloads HAProxy. The `-o`, `-O`, `-Q` and `-x` flags ask for supervision changes gopherd cannot make at runtime, so they exit 100 with an explanation instead. New scripts should call `gopherd` directly.

### Running Data Plane API images read-only

The s6-tagged images can run with a read-only root filesystem (`--read-only`) when the directories they write to are volumes. With the shipped `/usr/local/etc/haproxy/dataplaneapi.yml` those are two trees:

- `/usr/local/etc/haproxy` holds `haproxy.cfg` and `dataplaneapi.yml`, which Data Plane API rewrites, and the directories it stores uploaded files in: `maps` (`maps_dir`), `ssl` (`ssl_certs_dir`), `general` (`general_storage_dir`) and `spoe` (`spoe_dir`).
- `/usr/local/var/lib/dataplaneapi` holds Data Plane API's internal state in `storage` (`dataplane_storage_dir`), along with its `transactions` and configuration `backups`.

`/run` (the gopherd and HAProxy sockets) and `/tmp` (the SPOE transaction directory) must be writable as well, but need not persist, so a `tmpfs` is enough:

```console
$ docker run -d --name my-running-haproxy --read-only \
    --tmpfs /run --tmpfs /tmp \
    -v haproxy-config:/usr/local/etc/haproxy \
    -v haproxy-dataplaneapi:/usr/local/var/lib/dataplaneapi \
    -p 80:80 -p 443:443 -p 5555:5555 \
    haproxytech/haproxy-ubuntu:s6-3.4
```

Docker fills an empty named volume with the image's files on first use, so the container starts from the default configuration. The generated admin password, configuration changes, maps, certificates and SPOE files are then kept when the container is recreated. To read the password:

```console
$ docker exec my-running-haproxy grep password: /usr/local/etc/haproxy/dataplaneapi.yml
```

A bind-mounted host directory is not filled in, and without `haproxy.cfg` and `dataplaneapi.yml` neither service can start, so copy the defaults out of the image first:

```console
$ docker create --name haproxy-defaults haproxytech/haproxy-ubuntu:s6-3.4
$ docker cp haproxy-defaults:/usr/local/etc/haproxy/. /srv/haproxy/config/
$ docker cp haproxy-defaults:/usr/local/var/lib/dataplaneapi/. /srv/haproxy/dataplaneapi/
$ docker rm haproxy-defaults
```

Then use `-v /srv/haproxy/config:/usr/local/etc/haproxy -v /srv/haproxy/dataplaneapi:/usr/local/var/lib/dataplaneapi` in place of the named volumes. If the configuration directory is not writable, the container exits at start instead of serving Data Plane API with the shipped `admin` password.

# License

View [license information](https://raw.githubusercontent.com/haproxy/haproxy/master/LICENSE) for the software contained in this image.

As with all Docker images, these likely also contain other software which may be under other licenses (such as Bash, etc from the base distribution, along with any direct or indirect dependencies of the primary software being contained).
