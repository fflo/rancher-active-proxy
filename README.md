[![build](https://github.com/fflo/rancher-active-proxy/actions/workflows/build.yml/badge.svg)](https://github.com/fflo/rancher-active-proxy/actions/workflows/build.yml) ![nginx 1.30](https://img.shields.io/badge/nginx-1.30-brightgreen.svg) ![License MIT](https://img.shields.io/badge/license-MIT-blue.svg)

> **2026 maintenance fork.** This fork rebuilds the image from source (the upstream
> `fflo/rancher-active-proxy` image and its GitLab build artifacts are no longer
> maintained), pins every component, and hardens the generated nginx configuration.
> See [Building and upgrading](#building-and-upgrading) and the [CHANGELOG](CHANGELOG).
> Rancher v1 itself is end-of-life; keep the proxy host patched and treat it as the
> only thing exposed to the internet.

If you look for a Kubernetes version : Have a look to [Kube Active Proxy](https://github.com/adi90x/kube-active-proxy)

## Rancher Active Proxy

Rancher Active Proxy is an all-in-one reverse proxy for [Rancher](http://rancher.com), supporting Letsencrypt out of the box !

Rancher Active Proxy is based on the excellent idea of [jwilder/nginx-proxy](https://github.com/jwilder/nginx-proxy).

Rancher Active Proxy replaces docker-gen with rancher-gen (a fork of the also excellent [janeczku/go-rancher-gen](https://github.com/janeczku/go-rancher-gen) adding some more functions). Its source now lives in [`rancher-gen/`](rancher-gen/) in this repository and is compiled as part of the image build.

Rancher Active Proxy use label instead of environmental value.

Images are published to Docker Hub as [`fflo/rancher-active-proxy`](https://hub.docker.com/r/fflo/rancher-active-proxy) (`latest` from master, `vX.Y.Z` from tags) and rebuilt weekly so nginx, certbot and ModSecurity security updates are picked up.

### Easy Setup with catalog

Add `https://github.com/fflo/rancher-active-proxy.git` to your custom catalog list( Rancher > Admin > Settings ).

Then go to catalog and install Rancher Active Proxy !

### Usage

Minimal Params To run it:

    $ docker run -d -p 80:80 -p 443:443 -v rap-letsencrypt:/etc/letsencrypt fflo/rancher-active-proxy

Then start any containers you want proxied with a label `rap.host=subdomain.youdomain.com`

    $ docker run -l rap.host=foo.bar.com  ...

The containers being proxied must [expose](https://docs.docker.com/engine/reference/run/#expose-incoming-ports) the port to be proxied, either by using the `EXPOSE` directive in their `Dockerfile` or by using the `--expose` flag to `docker run` or `docker create`.

Provided your DNS is setup to forward foo.bar.com to the a host running `rancher-active-proxy`, the request will be routed to a container with the `rap.host` label set.

#### Summary of available labels for proxied containers.


|       Label                |            Description         |
| ---------------------------|------------------------------- |
| `rap.host`                 | Virtual host to use ( several value could be separate by `,` )
| `rap.port`                 | Port of the container to use ( only needed if several port are exposed ). Default `Expose Port` or `80`
| `rap.proto`                | Protocol used to contact container ( http,https,uwsgi ). Default : `http`
| `rap.timeout`              | Timeout for reading from this container ( in seconds ). Default : nginx default (60s)
| `rap.cert_name`            | Certificate name to use for the virtual host. Default `rap.host`
| `rap.https_method`         | Https method (redirect, noredirect, nohttps). Default : `redirect`
| `rap.hsts`                 | HSTS header on https hosts: `off`, `includeSubDomains` or `preload`. Default : `max-age=31536000` only
| `rap.le_host`              | Certificate to create/renew with Letsencrypt
| `rap.le_email`             | Email to use for Letsencrypt
| `rap.le_test  `            | Set to true to use stagging letsencrypt server
| `rap.le_bypass`            | Set to true to create a special bypass to use LE
| `rap.http_listen_ports`    | External Port you want Rancher-Active-Proxy to listen to http for this server ( Default : `80` )
| `rap.https_listen_ports`   | External Port you want Rancher-Active-Proxy to listen to https for this server ( Default : `443` )
| `rap.server_tokens`    	 | Enable to specify the server_token value per container
| `rap.client_max_body_size` | Enable to specify the client_max_body_size directive per container
| `rap.rap_name`             | If `RAP_NAME` is specified for a RAP instance only container with label value matching `RAP_NAME` value will be publish
| `rap.rate_limit`           | Requests per client IP for this host, e.g. `10r/s`, `600r/m` or `off`. Default : `RATE_LIMIT`
| `rap.rate_burst`           | Requests a client may burst above the rate before getting `429`. Default : `RATE_BURST`
| `rap.conn_limit`           | Concurrent connections per client IP, or `off`. Default : `CONN_LIMIT`
| `rap.waf`                  | ModSecurity/OWASP CRS for this host: `on`, `detect` (log only) or `off`. Default : `WAF`
| `rap.security_headers`     | `off` to drop the `X-Content-Type-Options`, `X-Frame-Options` and `Referrer-Policy` headers. Default : `SECURITY_HEADERS`

Label values are validated before they are written into the nginx configuration:
hostnames must be valid DNS names, ports must be numeric, and free-text values
(`rap.proto`, `rap.cert_name`, `rap.client_max_body_size`, ...) may not contain
whitespace, quotes, `;`, `{`, `}` or `#`. A service with an invalid value is skipped
(with a comment in the generated config) instead of breaking the proxy for everyone.

#### Summary of environment variable available for Rancher Active Proxy.

|       Label        |            Description         |
| ------------------ | ------------------------------ |
| `DEBUG`            | Set to `true` to enable more output. Default : `False`
| `CRON`             | Cron like expression to define when certs are renew. Default : `0 2 * * *`
| `DEFAULT_HOST`     | Default Nginx host.
| `DEFAULT_EMAIL`    | Default Email for Letsencrypt. Must be a real address; hosts without `rap.le_email` are skipped if it is missing.
| `RAP_DEBUG` 		 | Define Rancher-Gen-Rap verbosity (Valid values: "debug", "info", "warn", and "error"). Default: `info`
| `DEFAULT_PORT` 	 | Default port use for containers ( Default : `80` )
| `SPECIFIC_HOST` 	 | Limit RAP to only containers of a specific host name
| `RAP_NAME` 	     | If specify RAP will only publish service with `rap.rap_name = RAP_NAME`
| `ACME_INTERNAL` 	 | Enable passing ACME request to another RAP instance ( check PR #48)
| `LETSENCRYPT_DELAY` | Seconds to wait before contacting Let's Encrypt after the host list changed ( Default : `10` )
| `RATE_LIMIT`       | Requests per client IP allowed on every host, e.g. `30r/s`, `600r/m` or `off` ( Default : `30r/s` )
| `RATE_BURST`       | Burst allowance above `RATE_LIMIT` before `429 Too Many Requests` ( Default : `60` )
| `CONN_LIMIT`       | Concurrent connections per client IP, or `off` ( Default : `100` )
| `REAL_IP_FROM`     | Comma-separated IPs/CIDRs of trusted upstream proxies or CDNs; their `X-Forwarded-For` becomes the client IP for limits, logs and the WAF
| `WAF`              | Web application firewall mode for every host: `on`, `detect` (log only) or `off` ( Default : `detect` )
| `WAF_PARANOIA`     | OWASP CRS paranoia level 1-4; higher = stricter, more false positives ( Default : `1` )
| `WAF_ANOMALY_INBOUND` / `WAF_ANOMALY_OUTBOUND` | CRS anomaly score thresholds ( Default : `5` / `4` )
| `SECURITY_HEADERS` | `off` to disable the default browser hardening headers ( Default : `on` )
| `TZ`               | Time zone for cron and log timestamps ( Default : `UTC` )

#### Quick Summary of interesting volume to mount.

|       Path            |            Description         |
| --------------------- | ------------------------------ |
| `/etc/letsencrypt`    | Folder with all certificates used for https and Letsencrypt parameters
| `/etc/nginx/htpasswd` | Basic Authentication Support ( file should be `rap.host`)
| `/etc/nginx/vhost.d`  | Specifc vhost configuration ( file should be `rap.host`) . Location configuration should end with `_location`

#### Special Attention for standalone containers

Rancher Active Proxy is also able to work for standalone containers on the host it is launched.

There is only one limit to this : You should not use the same host name ( `rap.host` label ) for a standalone container and for a service.

This feature even enables you to proxy rancher-server, just start it with something like that :

`docker run -d --restart=unless-stopped -p 8080:8080 --name=rancher-server -l rap.host=admin.foo.com -l rap.port=8080 -l rap.le_host=admin.foo.com -l  rap.le_email=foo@bar.com -l io.rancher.container.pull_image=always rancher/server`

In this case `admin.foo.com` will enable you to acces rancher administration, but it is better to keep port 8080 exposed and use `http://foo.com:8080` as the host registration URL.

#### Let's Encrypt support out of box

Rancher Active Proxy is using `certbot` from Let's Encrypt in order to automatically get SSL certificates for containers.

In order to enable that feature you need to add `rap.le_host` label to the container ( you probably want it to be equal to `rap.host`)

And you should either start Rancher Active Proxy with environment variable `DEFAULT_EMAIL` or specify `rap.le_email` as a container label.

If you are developing I recommend to add `rap.le_test=true` to the container in order to use Let's Encrypt staging environment and to not exceed limits.

#### SAN certificates

Rancher Active Proxy support SAN certifcates ( one certificate for several domains ).

To create a SAN certificate you need to separate hostnames with ";" ( instead of "," for separate domains)

`rap.le_host=admin.foo.com;api.foo.com;mail.foo.com`

This will create a single certificate matching : admin.foo.com, api.foo.com, mail.foo.com .
The certificate created will be named `admin.foo.com` but symlink will be create to match all domains.


### Multiple Ports

If your container exposes multiple ports, Rancher Active Proxy will use `rap.port` label, then use the exposed port if there is only one port exposed, or default to `DEFAULT_PORT` environmental variable ( which is set by default to `80` ).
Or you can try your hand at the [Advanced `rap.host` syntax](#advanced-raphost-syntax).

### Special ByPass for Let's Encrypt

If your container uses its own letsencrypt process to get some certificates
Set `rap.le_bypass` to `true` to add a location to the http server block to forward `/.well-known/acme-certificate/` to upstream through http instead of redirecting it to https

### Advanced `rap.host` syntax

Using the Advanced `rap.host` syntax you can specify multiple host names to each go to their own backend port.
Basically this provides support for `rap.host`, `rap.port`, and `rap.proto` all in one field.

For example, given the following:

```
rap.host=api.example.com=>http:80,api-admin.example.com=>http:8001,secure.example.com=>https:8443
```

This would yield 3 different server/upstream configurations...

 1. Requests for api.example.com would route to this container's port 80 via http
 2. Requests for api-admin.example.com would route to this containers port 8001 via http
 3. Requests for secure.example.com would route to this containers port 8443 via https


### Multiple Listening Port

If needed you can use Rancher-Active-Proxy to listen for different ports.

`docker run -d -p 8081:8081 -p 81:81  fflo/rancher-active-proxy`

In this case, you can specify on which port Rancher Active Proxy should listen for a specific hostname :

`docker run -d -l rap.host=foo.bar.com -l rap.http_listen_ports="81,8081" -l rap.port="53" containerexposing/port53`

In this situation Rancher Active Proxy will listen for request matching `rap.host` on both port `81` and `8081` of your host
and route those request to port `53` of your container.

Likewise, `rap.https_listen_ports` will work for https requests.

If you are not using port `80` and `443` at all you won't be able to use Let's Encrypt Automatic certificates.

### Specific Host Name

Using environmental value `SPECIFIC_HOST` you can limit Rancher Active Proxy to containers running on a single host.

Just start Rancher Active Proxy like that : `docker run -d -p 80:80 -e SPECIFIC_HOST=Hostnameofthehost fflo/rancher-active-proxy`

### Remove Script

Rancher Active Proxy provides an easy script to revoke/delete a certificate.

Run it inside the running proxy container: `docker exec <proxy container> /app/remove admin.foo.com`

The argument is the certificate name, i.e. the first host of the `rap.le_host` label. For a SAN
certificate (`admin.foo.com;api.foo.com`) one call removes the whole certificate and every
nginx link that pointed at it. `/app/remove '*'` deletes all certificates. Names are no longer
treated as prefixes/globs.

Do not forget to delete the label on the container before using that script or it will be recreated on next update.

### Per-host server configuration

If you want to 100% personalize your server section on a per-`rap.host` basis, add your server configuration in a file under `/etc/nginx/vhost.d`
The file should use the suffix `_server`.

For example, if you have a virtual host named `app.example.com` and you have configured a proxy_cache `my-cache` in another custom file, you could tell it to use a proxy cache as follows:

    $ docker run -d -p 80:80 -p 443:443 -v /path/to/vhost.d:/etc/nginx/vhost.d:ro fflo/rancher-active-proxy

You should therefore have a file `app.example.com_server` in the `/etc/nginx/vhost.d` folder that contains the whole server block you want to use :

```
server {
        server_name app.example.com
        listen 80;
        access_log /var/log/nginx/access.log vhost;

        location / {
                proxy_pass http://app.example.com;
        }
}

```

If you are using multiple hostnames for a single container (e.g. `rap.host=example.com,www.example.com`), the virtual host configuration file must exist for each hostname.
If you would like to use the same configuration for multiple virtual host names, you can use a symlink.

### Per-host server default configuration

If you want most of your virtual hosts to use a default single `server` block configuration and then override it on a few specific ones, add a `/etc/nginx/vhost.d/default_server` file.
This file will be used on any virtual host which does not have a `/etc/nginx/vhost.d/{rap.host}_server` file associated with it.

### Limit RAP to some containers

If you want a RAP instance to only publish some specific containers/services, you can start the RAP container with environment variable `RAP_NAME = example`
In that situation, all containers to be published by this instance of RAP should have a label `rap.rap_name = example`
If a container should be published by several RAP instances just use a label matching regex like `rap.rap_name = internal,external` to be published by RAP instance named `internal` or `external`

***

The below part is mostly taken from jwilder/nginx-proxy [README](https://github.com/jwilder/nginx-proxy/blob/master/README.md) and modified to reflect Rancher Active Proxy

### Multiple Hosts

If you need to support multiple virtual hosts for a container, you can separate each entry with commas.  For example, `foo.bar.com,baz.bar.com,bar.com` and each host will be setup the same.

### Wildcard Hosts

You can also use wildcards at the beginning and the end of host name, like `*.bar.com` or `foo.bar.*`. Or even a regular expression, which can be very useful in conjunction with a wildcard DNS service like [xip.io](http://xip.io), using `~^foo\.bar\..*\.xip\.io` will match `foo.bar.127.0.0.1.xip.io`, `foo.bar.10.0.2.2.xip.io` and all other given IPs. More information about this topic can be found in the nginx documentation about [`server_names`](http://nginx.org/en/docs/http/server_names.html).

### SSL Backends

If you would like the reverse proxy to connect to your backend using HTTPS instead of HTTP
set `rap.proto=https` on the backend container.

### uWSGI Backends

If you would like to connect to uWSGI backend, set `rap.proto=uwsgi` on the backend container.
Your backend container should than listen on a port rather than a socket and expose that port.

### Default Host

To set the default host for nginx use the env var `DEFAULT_HOST=foo.bar.com` for example :

    $ docker run -d -p 80:80 -e DEFAULT_HOST=foo.bar.com fflo/rancher-active-proxy

### SSL Support

SSL is supported using single host, wildcard and SNI certificates using naming conventions for certificates
or optionally specifying a cert name (for SNI) as an environment variable.

To enable SSL:

    $ docker run -d -p 80:80 -p 443:443 -v /path/to/certs:/etc/nginx/certs  fflo/rancher-active-proxy

The contents of `/path/to/certs` should contain the certificates and private keys for any virtual
hosts in use.  The certificate and keys should be named after the virtual host with a `.crt` and
`.key` extension.  For example, a container with label `rap.host=foo.bar.com` should have a
`foo.bar.com.crt` and `foo.bar.com.key` file in the certs directory.

If you are running the container in a virtualized environment (Hyper-V, VirtualBox, etc...),
`/path/to/certs` must exist in that environment or be made accessible to that environment.
By default, Docker is not able to mount directories on the host machine to containers running in a virtual machine.

### Diffie-Hellman Groups

Let's Encrypt hosts use the RFC 7919 `ffdhe2048` group, installed as `/etc/letsencrypt/dhparam.pem`
on first start (replace that file with your own parameters if you prefer; it is never overwritten).
For manually provided certificates, the file should be named after the virtual host with a
`dhparam` suffix and `.pem` extension. For example, a container with `rap.host=foo.bar.com`
should have a `foo.bar.com.dhparam.pem` file in the certs directory.

### Wildcard Certificates

Wildcard certificates and keys should be named after the domain name with a `.crt` and `.key` extension.
For example `rap.host=foo.bar.com` would use cert name `bar.com.crt` and `bar.com.key`.

### SNI

If your certificate(s) supports multiple domain names, you can start a container with `rap.cert_name=<name>`
to identify the certificate to be used.  For example, a certificate for `*.foo.com` and `*.bar.com`
could be named `shared.crt` and `shared.key`.  A container running with `rap.host=foo.bar.com`
and `rap.cert_name=shared` will then use this shared cert.

### How SSL Support Works

The TLS configuration follows the current [Mozilla "intermediate" profile](https://ssl-config.mozilla.org/#server=nginx&config=intermediate):
TLS 1.2 and 1.3 only, AEAD ciphers with forward secrecy, client cipher preference, HTTP/2,
session cache without session tickets, and HSTS (tunable per host with `rap.hsts`).
Requests for a host name that is not configured (or a bare IP) are answered with a
generated self-signed certificate and a `503`, so a tenant's certificate is never presented
for a foreign host name. Place your own `default.crt`/`default.key` in `/etc/nginx/certs` to
override it. `server_tokens` is `off` by default.

The default behavior for the proxy when port 80 and 443 are exposed is as follows:

* If a container has a usable cert, port 80 will redirect to 443 for that container so that HTTPS
is always preferred when available.
* If the container does not have a usable cert, a 503 will be returned.

In the latter case the self-signed default certificate is used, so the browser gets a certificate
warning followed by a 503 instead of a connection error.

To serve traffic in both SSL and non-SSL modes without redirecting to SSL, you can include the
label  `rap.https_method=noredirect` (the default is `rap.https_method=redirect`).  You can also
disable the non-SSL site entirely with `rap.https_method=nohttp`. `rap.https_method` must be specified
on each container for which you want to override the default behavior.  If `rap.https_method=noredirect` is
used, Strict Transport Security (HSTS) is disabled to prevent HTTPS users from being redirected by the
client.  If you cannot get to the HTTP site after changing this setting, your browser has probably cached
the HSTS policy and is automatically redirecting you back to HTTPS.  You will need to clear your browser's
HSTS cache or use an incognito window / different browser.

### Basic Authentication Support

In order to be able to secure your virtual host, you have to create a file named as its equivalent `rap.host` label on directory
/etc/nginx/htpasswd/`rap.host`

```
$ docker run -d -p 80:80 -p 443:443 \
    -v /path/to/htpasswd:/etc/nginx/htpasswd \
    -v /path/to/certs:/etc/nginx/certs \
    fflo/rancher-active-proxy
```

You'll need apache2-utils on the machine where you plan to create the htpasswd file.
Or you can use an nginx container to create the file ( using OpenSSL as explained in [Nginx Readme](http://wiki.nginx.org/Faq#How_do_I_generate_an_.htpasswd_file_without_having_Apache_tools_installed.3F) )

`docker run -it nginx printf "Username_to_use:$(openssl passwd -crypt Password_to_use)\n" >> /path/to/htpasswd/{rap.host}`

A default htpasswd can be used to secure all hosts using this proxy. Good for development environments to keep prying eyes out. To use, create the htpasswd file named 'default' here: `/etc/nginx/htpasswd/default`.

### Custom Nginx Configuration

If you need to configure Nginx beyond what is possible using environment variables, you can provide custom configuration files on either a proxy-wide or per-`rap.host` basis.

### Replacing default proxy settings

If you want to replace the default proxy settings for the nginx container, add a configuration file at `/etc/nginx/proxy.conf`. A file with the default settings would
look like this:

```Nginx
# HTTP 1.1 support
proxy_http_version 1.1;
proxy_buffering off;
proxy_set_header Host $http_host;
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection $proxy_connection;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $proxy_x_forwarded_proto;
proxy_set_header X-Forwarded-Port $proxy_x_forwarded_port;

# Mitigate httpoxy attack (see README for details)
proxy_set_header Proxy "";
```

***NOTE***: If you provide this file it will replace the defaults; you may want to check the nginx.tmpl file to make sure you have all of the needed options.

***NOTE***: The default configuration blocks the `Proxy` HTTP request header from being sent to downstream servers.  This prevents attackers from using the so-called [httpoxy attack](http://httpoxy.org).  There is no legitimate reason for a client to send this header, and there are many vulnerable languages / platforms (`CVE-2016-5385`, `CVE-2016-5386`, `CVE-2016-5387`, `CVE-2016-5388`, `CVE-2016-1000109`, `CVE-2016-1000110`, `CERT-VU#797896`).

### Proxy-wide

To add settings on a proxy-wide basis, add your configuration file under `/etc/nginx/conf.d` using a name ending in `.conf`.

This can be done in a derived image by creating the file in a `RUN` command or by `COPY`ing the file into `conf.d`:

```Dockerfile
FROM fflo/rancher-active-proxy
RUN { \
      echo 'server_tokens off;'; \
      echo 'client_max_body_size 100m;'; \
    } > /etc/nginx/conf.d/my_proxy.conf
```

Or it can be done by mounting in your custom configuration in your `docker run` command:

    $ docker run -d -p 80:80 -p 443:443 -v /path/to/my_proxy.conf:/etc/nginx/conf.d/my_proxy.conf:ro fflo/rancher-active-proxy

### Per-VIRTUAL_HOST

To add settings on a per-`rap.host` basis, add your configuration file under `/etc/nginx/vhost.d`. Unlike in the proxy-wide case, which allows multiple config files with any name ending in `.conf`, the per-`rap.host` file must be named exactly after the `rap.host`.

In order to allow virtual hosts to be dynamically configured as backends are added and removed, it makes the most sense to mount an external directory as `/etc/nginx/vhost.d` as opposed to using derived images or mounting individual configuration files.

For example, if you have a virtual host named `app.example.com`, you could provide a custom configuration for that host as follows:

    $ docker run -d -p 80:80 -p 443:443 -v /path/to/vhost.d:/etc/nginx/vhost.d:ro fflo/rancher-active-proxy
    $ { echo 'server_tokens off;'; echo 'client_max_body_size 100m;'; } > /path/to/vhost.d/app.example.com

If you are using multiple hostnames for a single container (e.g. `rap.host=example.com,www.example.com`), the virtual host configuration file must exist for each hostname. If you would like to use the same configuration for multiple virtual host names, you can use a symlink:

    $ { echo 'server_tokens off;'; echo 'client_max_body_size 100m;'; } > /path/to/vhost.d/www.example.com
    $ ln -s /path/to/vhost.d/www.example.com /path/to/vhost.d/example.com

### Per-VIRTUAL_HOST default configuration

If you want most of your virtual hosts to use a default single configuration and then override on a few specific ones, add those settings to the `/etc/nginx/vhost.d/default` file. This file
will be used on any virtual host which does not have a `/etc/nginx/vhost.d/{rap.host}` file associated with it.

### Per-VIRTUAL_HOST location configuration

To add settings to the "location" block on a per-`rap.host` basis, add your configuration file under `/etc/nginx/vhost.d`
just like the previous section except with the suffix `_location`.

For example, if you have a virtual host named `app.example.com` and you have configured a proxy_cache `my-cache` in another custom file, you could tell it to use a proxy cache as follows:

    $ docker run -d -p 80:80 -p 443:443 -v /path/to/vhost.d:/etc/nginx/vhost.d:ro fflo/rancher-active-proxy
    $ { echo 'proxy_cache my-cache;'; echo 'proxy_cache_valid  200 302  60m;'; echo 'proxy_cache_valid  404 1m;' } > /path/to/vhost.d/app.example.com_location

If you are using multiple hostnames for a single container (e.g. `rap.host=example.com,www.example.com`), the virtual host configuration file must exist for each hostname. If you would like to use the same configuration for multiple virtual host names, you can use a symlink:

    $ { echo 'proxy_cache my-cache;'; echo 'proxy_cache_valid  200 302  60m;'; echo 'proxy_cache_valid  404 1m;' } > /path/to/vhost.d/app.example.com_location
    $ ln -s /path/to/vhost.d/www.example.com /path/to/vhost.d/example.com

### Per-VIRTUAL_HOST location default configuration

If you want most of your virtual hosts to use a default single `location` block configuration and then override on a few specific ones, add those settings to the `/etc/nginx/vhost.d/default_location` file. This file
will be used on any virtual host which does not have a `/etc/nginx/vhost.d/{rap.host}` file associated with it.

## Flood (DoS) protection

Every generated host gets nginx `limit_req` / `limit_conn` rules keyed on the client IP:
by default 30 requests per second with a burst of 60, and at most 100 concurrent connections.
Clients above that get `429 Too Many Requests` (logged at `warn` level in the nginx error log).
Tune proxy-wide with `RATE_LIMIT`, `RATE_BURST`, `CONN_LIMIT` or per host with `rap.rate_limit`,
`rap.rate_burst`, `rap.conn_limit`; `off` disables a limit. Slow-client (slowloris) and oversized
header probes are cut off by short `client_*_timeout`s and small header buffers, and HTTP/2
streams per connection are capped (`/etc/nginx/conf.d/00-security.conf`).

If the proxy sits behind a CDN or another load balancer, set `REAL_IP_FROM` to that proxy's
address ranges; otherwise every request would appear to come from the CDN and share one limit.

A reverse proxy can only absorb application-layer floods. Volumetric attacks that saturate the
host's uplink must be handled upstream (your hosting provider, a CDN, or a firewall in front of
the Rancher hosts).

## Web application firewall (ModSecurity + OWASP CRS)

The image ships ModSecurity v3 with the [OWASP Core Rule Set](https://coreruleset.org/) and
evaluates every request against it (SQL injection, XSS, path traversal, scanner signatures, ...).
The rule set is loaded once; each `rap.host` runs in one of three modes:

| Mode     | Effect |
| -------- | ------ |
| `detect` | **default** — matching requests are logged (JSON audit record on stdout) but still proxied |
| `on`     | matching requests are blocked with `403` |
| `off`    | ModSecurity is not run for this host |

Roll it out by watching `docker logs` for a while in `detect` mode, adding exclusions for
legitimate false positives, and then switching the proxy (`WAF=on`) or individual hosts
(`rap.waf=on`) to blocking. Let's Encrypt challenge requests are never inspected.

Exclusions live in the `/etc/nginx/vhost.d` volume as plain ModSecurity rule files:

| File                               | Scope |
| ---------------------------------- | ----- |
| `vhost.d/default_modsec_before`    | proxy-wide, loaded before the CRS rules (e.g. `SecRuleRemoveById`, `ctl:ruleRemoveTargetById`) |
| `vhost.d/default_modsec`           | proxy-wide, loaded after the CRS rules |
| `vhost.d/<rap.host>_modsec`        | only for that host |

Example `vhost.d/wiki.example.com_modsec` for an application that legitimately posts HTML:

```
SecRuleRemoveById 941100 941110 941160
SecRule REQUEST_URI "@beginsWith /api/upload" "id:10001,phase:1,pass,nolog,ctl:ruleEngine=Off"
```

`WAF_PARANOIA` (1-4) and the anomaly thresholds follow the CRS documentation; level 1 is right for
almost everybody. The engine configuration is `/etc/modsecurity.d/modsecurity.conf` in the image.

## Building and upgrading

```sh
docker build -t rancher-active-proxy:local .
```

The build compiles `rancher-gen` and `forego` from pinned, checksum-verified Go modules, and
libmodsecurity plus its nginx connector against the exact nginx version of the runtime image
(`--with-compat`, the same recipe the OWASP CRS container image uses), then copies the results
into `nginx:1.30-alpine`. The CRS release tarball is GPG-verified. Expect the ModSecurity stage to
take several minutes on first build; it is cached afterwards. A local `docker build` produces an
image for the machine you run it on (so on an Apple Silicon Mac add `--platform linux/amd64` to get
one for x86 Rancher hosts; that is slow under emulation).

The published image is **multi-architecture** (`linux/amd64` and `linux/arm64`): GitHub Actions
(`.github/workflows/build.yml`) compiles each architecture on a native runner, smoke-tests it,
merges both into one manifest under the version tags, scans it with Trivy and pushes it to Docker
Hub, so `docker pull fflo/rancher-active-proxy` works unchanged on x86 servers, ARM servers,
Raspberry Pi 4/5 and Apple Silicon. 32-bit ARM can be enabled in the workflow matrix at the cost
of an emulated build. The workflow needs the repository secrets `DOCKERHUB_USERNAME` and
`DOCKERHUB_TOKEN`. Tags: `latest` (master), `1.2.3` and `1.2` (from git tag `v1.2.3`), `sha-…`.

Upgrading an existing stack from the `adi90x` image:

1. Keep your `/etc/letsencrypt`, `/etc/nginx/vhost.d` and `/etc/nginx/htpasswd` volumes; they are
   used unchanged. Existing certificates are re-linked from the certbot lineages on start.
2. Set `DEFAULT_EMAIL` to a real address (the old `foo@bar.com` placeholder is rejected).
3. The `remove` script now takes an exact certificate name instead of a prefix.
4. `rap.timeout` must be a plain number of seconds and the port/proto in `rap.host=...=>proto:port`
   are validated; check the generated `/etc/nginx/conf.d/default.conf` for `# skipped` comments.
5. nginx 1.30 serves HTTP/2 via `http2 on;`; if you ship your own `vhost.d/*_server` blocks, drop the
   deprecated `listen ... http2` form.
6. The generated server blocks now carry their own `/.well-known/acme-challenge/` location; the
   copy that older versions injected into `vhost.d/default` is removed automatically on start.
7. Rate limiting and the WAF in `detect` mode are active by default. Watch the logs for `429`s and
   ModSecurity audit records and tune `RATE_LIMIT` / `rap.waf` before switching the WAF to `on`.
8. `add_header` directives in your own `vhost.d/*_location` files replace the proxy's default
   security headers for that location (standard nginx inheritance); re-add the ones you want.

## Contributing

Do not hesitate to send issues or pull requests !

Automated Gitlab CI is used to build Rancher Active Proxy therefore send any pull request/issues to [Rancher Active Proxy on Gitlab.com](https://gitlab.com/fflo/rancher-active-proxy/)
