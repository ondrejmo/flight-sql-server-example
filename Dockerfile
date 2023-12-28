FROM debian:bookworm

ARG DUCKDB_VERSION="v0.9.2"
ARG UID=1000
ARG GID=1000

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
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/arrow.deb && \
    git clone --depth 1 "https://github.com/duckdb/duckdb.git" --branch "$DUCKDB_VERSION" --recurse-submodules && \
    cd duckdb && \
    GEN=ninja make && \
    cp build/release/duckdb /usr/local/bin && \
    cp build/release/src/libduckdb* /usr/local/lib/ && \
    cp src/include/duckdb.h src/include/duckdb.hpp /usr/local/include/ && \
    cp -R src/include/duckdb /usr/local/include/ && \
    cd .. && \
    rm -rf ./duckdb && \
    mkdir -p /app/build && \
    chown $UID:$GID -R /app && \
    cd /app/build && \
    cmake .. -GNinja -DCMAKE_PREFIX_PATH=${ARROW_HOME}/lib/cmake && \
    ninja && \
    mv flight_sql /usr/local/bin && \
    rm -rf /app/build

RUN groupadd -g $GID flight && \
    useradd --create-home --home-dir /home/flight --shell /bin/bash -u $UID -g $GID flight && \
    chown -R $UID:$GID /usr/local

USER 1000

EXPOSE 31337

ENTRYPOINT flight_sql --backend=duckdb --database-filename="${DATABASE_FILENAME}" --print-queries
