FROM debian:bookworm

ARG DUCKDB_VERSION="v0.9.2"
ARG UID=1000
ARG GID=1000

RUN apt-get update && \
    apt-get install -y \
    build-essential \
    cmake \
    gcc \
    git \
    ninja-build \
    libboost-all-dev \
    libsqlite3-dev \
    sqlite3 \
    ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

ADD https://apache.jfrog.io/artifactory/arrow/debian/apache-arrow-apt-source-latest-bookworm.deb /tmp/arrow.deb
RUN apt install -y /tmp/arrow.deb && \
    apt update && \
    apt install -y -V \
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
    rm -rf /var/lib/apt/lists/* /tmp/arrow.deb

RUN git clone --depth 1 "https://github.com/duckdb/duckdb.git" --branch "$DUCKDB_VERSION" --recurse-submodules && \
    cd duckdb && \
    GEN=ninja make && \
    cp build/release/duckdb /usr/local/bin && \
    cp build/release/src/libduckdb* /usr/local/lib/ && \
    cp src/include/duckdb.h src/include/duckdb.hpp /usr/local/include/ && \
    cp -R src/include/duckdb /usr/local/include/ && \
    cd .. && \
    rm -rf ./duckdb

RUN groupadd -g $GID flight && \
    useradd --create-home --home-dir /home/flight --shell /bin/bash -u $UID -g $GID flight && \
    chown -R $UID:$GID /usr/local && \
    mkdir -p /app/build && \
    chown $UID:$GID -R /app

USER 1000
COPY --chown=flight:flight ./CMakeLists.txt /app/
COPY --chown=flight:flight ./src /app/src

RUN cd /app/build && \
    cmake .. -GNinja -DCMAKE_PREFIX_PATH=${ARROW_HOME}/lib/cmake && \
    ninja && \
    mv flight_sql /usr/local/bin && \
    rm -rf /app/build

EXPOSE 31337

ENTRYPOINT flight_sql --backend=duckdb --database-filename="${DATABASE_FILENAME}" --print-queries
