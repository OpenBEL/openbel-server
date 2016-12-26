## Development

#### Local

Developing on openbel-api requires the following system dependencies:

- Git
- Java 8 (JDK)
- JRuby 9.x
- MongoDB 3.2
- SQLite 3.x

Setting up data:

- To start you will have to obtain RDF resources and full-text search
  database containing biological concepts (e.g. annotations, namespaces).
  Obtain data from [OpenBEL Build Server](https://build.openbel.org/browse/OR).

Then follow a few steps:

1. Clone the *openbel-api* using Git.
  - `git clone git@github.com:OpenBEL/openbel-api.git`
2. Change directory to the cloned repository.
  - `cd openbel-api`
3. Clone submodules for local developement to the *subprojects/* directory.
  - `git submodule update`
4. Install bundle on JRuby.
  - `jruby -S gem install bundler`
5. Install *openbel-api* dependencies using bundler.
  - ` jruby -S bundle install --path .gems`
  - This ensures we isolate gem dependencies from other system gem paths.
  - Bundler saves this configuration so we don't need to specify *--path*
    again.
6. Run *bin/openbel-api* using bundler.
  - `jruby -S bundle exec bin/openbel-api --file config/config.yml`

If all went well you should see:

```
Puma starting in single mode...
* Version 3.1.0 (jruby 2.3.1), codename: El Niño Winter Wonderland
* Min threads: 0, max threads: 16
* Environment: development
* Listening on tcp://0.0.0.0:9292
Use Ctrl-C to stop
```

#### On Docker

First you will need to install [Docker](https://www.docker.com/).

- Linux: Install `docker` and `docker-compose` from your package manager.
- Mac OSX / Windows: Install [Docker Machine](https://docs.docker.com/machine/install-machine/) and
  [Docker Compose](https://docs.docker.com/compose/install/) by following the instructions on the Docker site.

Then follow a few steps:

1. Clone the *openbel-api* using Git.
  - `git clone git@github.com:OpenBEL/openbel-api.git`
2. Change directory to the cloned repository.
  - `cd openbel-api`
3. Clone submodules for local development to the *subprojects/* directory.
  - `git submodule update`

Then you will need to obtain the RDF store and full-text search database containing
biological concepts (e.g. annotation, namespaces). Download data from
[OpenBEL Build Server](https://build.openbel.org/browse/OR).

- Create the `data/` directory at the root of the `openbel-api`.
- Copy the RDF store to `data/rdf_store`.
- Copy full-text search SQLite database to `data/rdf_resources.db`.

The `data/` directory is used as a mounted volume to a docker container so it can be
accessed within the `openbel-api`.

Now create the `openbel-api` configuration file you will use in development. This will need
to point to the RDF store and full-text search database you create previously.

- Copy the `config/config.yml.example` to `config/config.yml`.
- Change the *resource_rdf.jena.tdb_directory* property to `/data/rdf_store`.
- Change the *resource_search.sqlite.database_file* to `/data/rdf_resources.db`.

Now you will need a local developer build using docker. This is accomplished by using
the *docker-compose.yml* layout.

Run the following to build from the base of the *openbel-api* directory.

1. Build the docker compose layout for the developer build.
  - `docker-compose build`
2. Run the docker compose layout to launch for your developer build.
  - `docker-compose up`
  - You may have to set a longer `COMPOSE_HTTP_TIMEOUT` if you receive a timeout error.
    - run the command `export COMPOSE_HTTP_TIMEOUT=300`

This can be done with the command: `export COMPOSE_HTTP_TIMEOUT=300` (5 minutes)

The *openbel-api* processes started successfully when you see the following log:

```
openbel-api_1   | Puma starting in single mode...
openbel-api_1   | * Version 3.1.0 (jruby 2.3.1), codename: El Niño Winter Wonderland
openbel-api_1   | * Min threads: 1, max threads: 2
openbel-api_1   | * Environment: development
mongodb_1       | 2016-11-22T01:14:40.986+0000 I NETWORK  [initandlisten] connection accepted from 172.19.0.4:54350 #1 (1 connection now open)
mongodb_1       | 2016-11-22T01:14:41.049+0000 I NETWORK  [conn1] end connection 172.19.0.4:54350 (0 connections now open)
mongodb_1       | 2016-11-22T01:14:41.052+0000 I NETWORK  [initandlisten] connection accepted from 172.19.0.4:54352 #2 (1 connection now open)
mongodb_1       | 2016-11-22T01:14:41.058+0000 I NETWORK  [conn2] end connection 172.19.0.4:54352 (0 connections now open)
mongodb_1       | 2016-11-22T01:14:41.064+0000 I NETWORK  [initandlisten] connection accepted from 172.19.0.4:54354 #3 (1 connection now open)
openbel-api_1   | log4j:WARN No appenders could be found for logger (org.apache.jena.info).
openbel-api_1   | log4j:WARN Please initialize the log4j system properly.
openbel-api_1   | log4j:WARN See http://logging.apache.org/log4j/1.2/faq.html#noconfig for more info.
mongodb_1       | 2016-11-22T01:14:41.795+0000 I NETWORK  [conn3] end connection 172.19.0.4:54354 (0 connections now open)
openbel-api_1   | * Listening on tcp://0.0.0.0:9292
openbel-api_1   | Use Ctrl-C to stop
```

Now with docker development you can change code and have it automatically reload:

- `app/` (*openbel-api*)
- `lib/` (*openbel-api*)
- `subprojects/`
  - `bel/`
  - `bel_parser/`
  - `bel-rdf-jena/`
  - `bel-search-sqlite/`
