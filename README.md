# Supported tags and respective `Dockerfile` links\n
-\t[`2.2-dev2`, `2.2`](https://github.com/haproxytech/haproxy-docker-ubuntu/blob/master/2.2/Dockerfile)
-\t[`2.1.3`, `2.1`](https://github.com/haproxytech/haproxy-docker-ubuntu/blob/master/2.1/Dockerfile)
-\t[`2.0.13`, `2.0`, `latest`](https://github.com/haproxytech/haproxy-docker-ubuntu/blob/master/2.0/Dockerfile)
-\t[`1.9.13`, `1.9`](https://github.com/haproxytech/haproxy-docker-ubuntu/blob/master/1.9/Dockerfile)
-\t[`1.8.23`, `1.8`](https://github.com/haproxytech/haproxy-docker-ubuntu/blob/master/1.8/Dockerfile)
-\t[`1.7.12`, `1.7`](https://github.com/haproxytech/haproxy-docker-ubuntu/blob/master/1.7/Dockerfile)
-\t[`1.6.15`, `1.6`](https://github.com/haproxytech/haproxy-docker-ubuntu/blob/master/1.6/Dockerfile)
-\t[`1.5.19`, `1.5`](https://github.com/haproxytech/haproxy-docker-ubuntu/blob/master/1.5/Dockerfile)

# Quick reference

-	**Where to get help**:  
	[HAProxy mailing list](mailto:haproxy@formilux.org), [HAProxy Community Slack](https://slack.haproxy.org/) or [#haproxy on FreeNode](irc://chat.freenode.net:6697/haproxy)

-	**Where to file issues**:  
	[https://github.com/haproxytech/haproxy-docker-ubuntu/issues](https://github.com/haproxytech/haproxy-docker-ubuntu/issues)

-	**Maintained by**:  
	[HAProxy Technologies](https://github.com/haproxytech)

-	**Supported architectures**: ([more info](https://github.com/docker-library/official-images#architectures-other-than-amd64))  
	[`amd64`](https://hub.docker.com/r/amd64/haproxy/)

-	**Image updates**:  
	[commits to `haproxytech/haproxy-docker-ubuntu`](https://github.com/haproxytech/haproxy-docker-ubuntu/commits/master), [top level `haproxytech/haproxy-docker-ubuntu` image folder](https://github.com/haproxytech/haproxy-docker-ubuntu)  

-	**Source of this description**:  
	[README.md](https://github.com/haproxytech/haproxy-docker-ubuntu/blob/master/README.md)

# What is HAProxy?

HAProxy is the fastest and most widely used open-source load balancer and application delivery controller. Written in C, it has a reputation for efficient use of both processor and memory. It can proxy at either layer 4 (TCP) or layer 7 (HTTP) and has additional features for inspecting, routing and modifying HTTP messages.

It comes bundled with a web UI, called the HAProxy Stats page, that you can use to monitor error rates, the volume of traffic and latency. Features can be toggled on by updating a single configuration file, which provides a syntax for defining routing rules, rate limiting, access controls, and more.

Other features include:

* SSL/TLS termination
* Gzip compression
* Health checking
* HTTP/2
* gRPC support
* Lua scripting
* DNS service discovery
* Automatic retries of failed conenctions
* Verbose logging

![logo](https://www.haproxy.org/img/HAProxyCommunityEdition_60px.png)

# How to use this image

This image is being shipped with a trivial sample configuration and for any real life use it should be configured according to the [extensive documentation](https://cbonte.github.io/haproxy-dconv/) and [examples](https://github.com/haproxy/haproxy/tree/master/examples). We will now show how to override shipped haproxy.cfg with one of your own.

## Create a `Dockerfile`

```dockerfile
FROM haproxytech/haproxy-ubuntu:2.0
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

## Directly via bind mount

```console
$ docker run -d --name my-running-haproxy -v /path/to/etc/haproxy:/usr/local/etc/haproxy:ro haproxytech/haproxy-ubuntu:2.0
```

Note that your host's `/path/to/etc/haproxy` folder should be populated with a file named `haproxy.cfg` as well as any other accompanying files local to `/etc/haproxy`.

### Reloading config

To be able to reload HAProxy configuration, you can send `SIGHUP` to the container:

```console
$ docker kill -s HUP my-running-haproxy
```

To achieve seamless reloads it is required to use `expose-fd listeners` and socket transfers which are not enabled by default. More on this topic is in the blog post [Truly Seamless Reloads with HAProxy](https://www.haproxy.com/blog/truly-seamless-reloads-with-haproxy-no-more-hacks/).

# License

View [license information](https://raw.githubusercontent.com/haproxy/haproxy/master/LICENSE) for the software contained in this image.

As with all Docker images, these likely also contain other software which may be under other licenses (such as Bash, etc from the base distribution, along with any direct or indirect dependencies of the primary software being contained).
