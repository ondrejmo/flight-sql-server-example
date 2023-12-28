FROM debian:bookworm AS builder

ARG DUCKDB_VERSION="v0.9.2"

COPY ./CMakeLists.txt /app/
COPY ./src /app/src

RUN apt-get update && \
    apt-get install -y \
        build-essential \
        cmake \
        gcc \
        git \
        wget \
        ninja-build \
        libboost-all-dev \
        libsqlite3-dev \
        sqlite3 \
        ca-certificates && \
    wget https://apache.jfrog.io/artifactory/arrow/debian/apache-arrow-apt-source-latest-bookworm.deb -O /tmp/arrow.deb && \
    apt install -y /tmp/arrow.deb && \
    apt update && \
    apt install -y  \
        libarrow-dev \
        libarrow-glib-dev \
        libarrow-dataset-dev \
        libarrow-dataset-glib-dev \
        libarrow-acero-dev \
        libarrow-flight-dev \
        libarrow-flight-glib-dev \
        libarrow-flight-sql-dev \
        libarrow-flight-sql-glib-dev \
        libgandiva-dev \
        libgandiva-glib-dev \
        libparquet-dev \
        libparquet-glib-dev && \
    git clone --depth 1 "https://github.com/duckdb/duckdb.git" --branch "$DUCKDB_VERSION" --recurse-submodules /tmp/duckdb && \
    cd /tmp/duckdb && \
    GEN=ninja make && \
    cp build/release/duckdb /usr/local/bin && \
    cp build/release/src/libduckdb* /usr/local/lib/ && \
    cp src/include/duckdb.h src/include/duckdb.hpp /usr/local/include/ && \
    cp -R src/include/duckdb /usr/local/include/ && \
    mkdir -p /app/build && \
    cd /app/build && \
    cmake .. -GNinja -DCMAKE_PREFIX_PATH=${ARROW_HOME}/lib/cmake && \
    ninja

FROM debian:bookworm

ARG UID=1000
ARG GID=1000

RUN groupadd -g $GID flight && \
    useradd --create-home --home-dir /home/flight --shell /bin/bash -u $UID -g $GID flight && \
    chown -R $UID:$GID /usr/local

ADD https://apache.jfrog.io/artifactory/arrow/debian/apache-arrow-apt-source-latest-bookworm.deb /tmp/arrow.deb
COPY --from=builder --chown=flight:flight /tmp/duckdb/build/release/duckdb /usr/local/bin/
COPY --from=builder --chown=flight:flight /tmp/duckdb/build/release/src/libduckdb_static.a /usr/local/lib/
COPY --from=builder --chown=flight:flight /tmp/duckdb/build/release/src/libduckdb.so /usr/local/lib/
COPY --from=builder --chown=flight:flight /tmp/duckdb/src/include/duckdb.h /tmp/duckdb/src/include/duckdb.hpp /usr/local/include/
COPY --from=builder --chown=flight:flight /tmp/duckdb/src/include/duckdb /usr/local/include/
COPY --from=builder --chown=flight:flight /app/build/flight_sql /usr/local/bin/

RUN apt update && \
    apt install -y /tmp/arrow.deb \
                   ca-certificates && \
    apt update && \
    apt-get install -y --no-install-recommends \
        libarrow-flight-sql1400 \
        libboost-program-options1.74.0 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/arrow.deb /app/build /tmp/duckdb

USER 1000

EXPOSE 31337

ENTRYPOINT flight_sql
CMD [ --backend=duckdb, --database-filename=/data/duck.db, --print-queries ]
