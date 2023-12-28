FROM debian:bookworm

# Install base utilities
RUN apt-get update && \
    apt-get install -y \
    build-essential \
    cmake \
    wget \
    gcc \
    git \
    unzip \
    ninja-build \
    libboost-all-dev \
    libsqlite3-dev \
    sqlite3 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install Apache Arrow (per https://arrow.apache.org/install/)
RUN apt update && \
    apt install -y -V ca-certificates lsb-release wget && \
    wget https://apache.jfrog.io/artifactory/arrow/$(lsb_release --id --short | tr 'A-Z' 'a-z')/apache-arrow-apt-source-latest-$(lsb_release --codename --short).deb && \
    apt install -y -V ./apache-arrow-apt-source-latest-$(lsb_release --codename --short).deb && \
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
    rm -rf /var/lib/apt/lists/*

 # Install DuckDB
ARG DUCKDB_VERSION="v0.9.2"
RUN wget "https://github.com/duckdb/duckdb/releases/download/${DUCKDB_VERSION}/libduckdb-linux-`dpkg --print-architecture`.zip" -O /tmp/duckdb.zip && \
    cd /tmp && \
    unzip -j /tmp/duckdb.zip && \
    cp libduckdb* /usr/local/lib/ && \
    cp duckdb.h /usr/local/include/ && \
    cp duckdb.hpp /usr/local/include/ && \
    git clone --branch $DUCKDB_VERSION --single-branch --depth 1 https://github.com/duckdb/duckdb.git && \
    cp -R duckdb/src/include/duckdb /usr/local/include/ && \
    rm /tmp/duckdb.zip

ARG APP_DIR=/opt/flight_sql

RUN useradd 1000 --create-home && \
    mkdir --parents ${APP_DIR} && \
    chown 1000:1000 ${APP_DIR} && \
    chown --recursive 1000:1000 /usr/local

WORKDIR ${APP_DIR}
USER 1000

# Build the Flight SQL application
COPY --chown=1000:1000 ./CMakeLists.txt ./
COPY --chown=1000:1000 ./src ./src
WORKDIR ${APP_DIR}
RUN mkdir build && \
    cd build && \
    cmake .. -GNinja -DCMAKE_PREFIX_PATH=${ARROW_HOME}/lib/cmake && \
    ninja && \
    mv flight_sql /usr/local/bin

EXPOSE 31337

ENTRYPOINT flight_sql --backend=duckdb --database-filename="${DATABASE_FILENAME}" --print-queries
