# ecocor-api

eXist extension providing REST API for EcoCor

## Getting started

```sh
git clone https://github.com/dh-network/ecocor-api.git
cd ecocor-api
docker compose up
```

We provide a [compose.yml](compose.yml) that allows to run an eXist database
with `ecocor-api` locally. With
[Docker installed](https://docs.docker.com/get-docker/) simply run:

```sh
docker compose up
```

This builds the necessary images and starts the respective docker containers.
The **eXist database** will become available under http://localhost:8090/.
To check that the EcoCor API is up run

```sh
curl http://localhost:8090/exist/restxq/ecocor/info
```

The configuration of the API (`/db/ecocor/config.xml`) is taken from the
environment variables `ECOCOR_API_BASE` (default: `https://ecocor.org/api`) and
`EXTRACTOR_SERVER` (default: `http://localhost:8040`) of the container, see
[compose.yml](compose.yml). The image itself sets no defaults for them. The
config is updated whenever the package is installed: a variable that is set
replaces the stored value, an unset one keeps it. In the Docker image the
package is only installed on the first start, i.e. with an empty data volume.

## Building the eXist extension

To package the ecocor-api code into an eXist extension archive (XAR) that can
be installed into an existing eXist DB instance run:

```sh
./build.sh
```

This creates an ecocor-x.x.x.xar archive in the `build` directory. It only
requires `git`, `sed` and `zip`. The version is derived from `git describe` and
can be overridden with the `VERSION` environment variable. `./build.sh clean`
removes the build artifacts.

Note that `build.sh` lists the files that go into the package explicitly. Any
new top-level file the app needs must be added there.

## Deployment

The `deploy.sh` script installs a XAR package into a running eXist DB using its
REST interface, replacing any installed version of `ecocor-api`. The corpus data
remains untouched. To deploy to the local instance from `docker compose`:

```sh
EXIST_PASSWORD=secret ./deploy.sh ecocor-latest.xar http://localhost:8090/exist
```

For a remote server open an SSH tunnel to its eXist port first and pass the
tunnel URL:

```sh
ssh -N -L 8888:localhost:8080 user@ecocor.org &
EXIST_PASSWORD=secret ./deploy.sh ecocor-latest.xar http://localhost:8888/exist
```

The [Deploy](.github/workflows/deploy.yml) GitHub workflow does the same for the
EcoCor production server when a release is published (not for pre-releases).
It can also be run manually from the Actions tab, e.g. to redeploy.

The server is configured in the `production`
[GitHub environment](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments):

| Name                 | Type     | Description                                          |
| -------------------- | -------- | ---------------------------------------------------- |
| `DEPLOY_KEY`         | secret   | SSH key of the user `github` on the server           |
| `EXIST_PASSWORD`     | secret   | eXist DB password                                    |
| `EXIST_USER`         | secret   | eXist DB user (optional, default `admin`)            |
| `DEPLOY_HOST`        | variable | server host name, e.g. `ecocor.org`                  |
| `DEPLOY_KNOWN_HOSTS` | variable | the server's SSH host key(s) in `known_hosts` format |
| `EXIST_PORT`         | variable | eXist port on the server (default `8080`)            |

The deployment branch rules of the environment should only allow `main` and
tags, and a tag ruleset should restrict who can create tags. Otherwise a manual
run can deploy any branch.

The workflow checks that `https://<DEPLOY_HOST>/api/info` reports the new
version after installing the package.

## Visual Studio Code integration

The [existdb-vscode](https://marketplace.visualstudio.com/items?itemName=eXist-db.existdb-vscode)
extension allows for developing XQuery code targeted at eXistdb and sync it with
a running database instance. We provide a configuration template that integrates
VS Code with the eXist instance from `docker compose`. Run

```sh
cp .existdb.json.tmpl .existdb.json
```

to create a configuration file and adjust the password if needed. For usage
details see the
[extension's documentation](https://marketplace.visualstudio.com/items?itemName=eXist-db.existdb-vscode).
