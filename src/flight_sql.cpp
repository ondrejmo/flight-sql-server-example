#include <cstdlib>
#include <csignal>
#include <iostream>
#include <fstream>
#include <pthread.h>
#include <filesystem>
#include <vector>
// #include <duckdb.h>

// #include <arrow/api.h>
#include <arrow/flight/client.h>
#include <arrow/flight/sql/client.h>
#include <arrow/flight/sql/server.h>
#include <arrow/table.h>
#include <arrow/util/logging.h>
#include <arrow/record_batch.h>

#include "sqlite/sqlite_server.h"
#include "duckdb/duckdb_server.h"

namespace flight = arrow::flight;
namespace flightsql = arrow::flight::sql;

int port = 31337;

arrow::Status printResults(
    std::unique_ptr<flight::FlightInfo> &results, 
    std::unique_ptr<flightsql::FlightSqlClient> &client,
    const flight::FlightCallOptions &call_options) {
        // Fetch each partition sequentially (though this can be done in parallel)
        for (const flight::FlightEndpoint& endpoint : results->endpoints()) {
            // Here we assume each partition is on the same server we originally queried, but this
            // isn't true in general: the server may split the query results between multiple
            // other servers, which we would have to connect to.

            // The "ticket" in the endpoint is opaque to the client. The server uses it to
            // identify which part of the query results to return.
            ARROW_ASSIGN_OR_RAISE(auto stream, client->DoGet(call_options, endpoint.ticket));
            // Read all results into an Arrow Table, though we can iteratively process record
            // batches as they arrive as well
            ARROW_ASSIGN_OR_RAISE(auto table, stream->ToTable());
            std::cout << table->ToString() << std::endl;
        }

    return arrow::Status::OK();
}

std::string readFileIntoString(const std::string& path) {
    auto ss = std::ostringstream{};
    std::ifstream input_file(path);
    if (!input_file.is_open()) {
        std::cerr << "Could not open the file - '"
             << path << "'" << std::endl;
        exit(EXIT_FAILURE);
    }
    ss << input_file.rdbuf();
    return ss.str();
}

bool checkIfSkip(std::string path, int query_id) {
    std::string query_id_str = std::to_string(query_id);

    if (path.find(query_id_str) != std::string::npos) {
        std::cout << "Skipping query: " << query_id << '\n';
        return true;
    }
    return false;
}

arrow::Status runQueries(
        std::unique_ptr<flightsql::FlightSqlClient> &client, 
        const std::string &query_path, 
        const std::vector<int> &skip_queries, 
        flight::FlightCallOptions &call_options
    ) {
    int skip_vector_it = 0;
    for (const auto & file : std::filesystem::directory_iterator(query_path)) {
        std::cout << file.path() << std::endl;
        if (skip_vector_it < skip_queries.size()) {
            if (checkIfSkip(file.path(), skip_queries.at(skip_vector_it))) {
                ++skip_vector_it;
                continue;
            }
        }
        std::string kQuery = readFileIntoString(file.path());

        std::cout << "Executing query: '" << kQuery << "'" << std::endl;
        ARROW_ASSIGN_OR_RAISE(auto flight_info, client->Execute(call_options, kQuery));

        if (flight_info != nullptr) {
            printResults(flight_info, client, call_options);
        }
    }

    return arrow::Status::OK();
}

arrow::Result<std::shared_ptr<arrow::flight::sql::FlightSqlServerBase>> CreateServer(
        const std::string &db_type, 
        const std::string &db_path
    ) {
    ARROW_ASSIGN_OR_RAISE(auto location,
                        arrow::flight::Location::ForGrpcTcp("0.0.0.0", port));
    arrow::flight::FlightServerOptions options(location);

    std::shared_ptr<arrow::flight::sql::FlightSqlServerBase> server = nullptr;

    if (db_type == "SQLite") {
        ARROW_ASSIGN_OR_RAISE(server,
                                arrow::flight::sql::sqlite::SQLiteFlightSqlServer::Create(db_path));
    } else if (db_type == "DuckDB") {
        duckdb::DBConfig config;
        ARROW_ASSIGN_OR_RAISE(server,
                                arrow::flight::sql::duckdbflight::DuckDBFlightSqlServer::Create(db_path, config));
    } else {
        std::string err_msg = "Unknown server type: --> ";
        err_msg += db_type;
        return arrow::Status::Invalid(err_msg);
    }

    if (server != nullptr) {
        ARROW_CHECK_OK(server->Init(options));
        // Exit with a clean error code (0) on SIGTERM
        ARROW_CHECK_OK(server->SetShutdownOnSignals({SIGTERM}));

        std::cout << "Server listening on localhost:" << server->port() << std::endl;
        return server;
    } else {
        std::string err_msg = "Unable to start the server";
        return arrow::Status::Invalid(err_msg);
    }
}

arrow::Result<std::unique_ptr<flightsql::FlightSqlClient>> CreateClient() {
    ARROW_ASSIGN_OR_RAISE(auto location,
                        arrow::flight::Location::ForGrpcTcp("localhost", port));
    arrow::flight::FlightServerOptions options(location);

    ARROW_ASSIGN_OR_RAISE(auto flight_client, flight::FlightClient::Connect(location));
    std::cout << "Connected to server: localhost:" << port << std::endl; 

    std::unique_ptr<flightsql::FlightSqlClient> client(
        new flightsql::FlightSqlClient(std::move(flight_client)));
    std::cout << "Client created." << std::endl;

    return client;
}

arrow::Status Main() {
    std::string db_path = "../data/TPC-H-small.duckdb";
    ARROW_ASSIGN_OR_RAISE(auto server, CreateServer("DuckDB", db_path));

    // // std::string query_path = "../queries/sqlite";
    // // std::vector<int> skip_queries = {17}; // the rest of the code assumes this is ORDERED vector!
    ARROW_ASSIGN_OR_RAISE(auto client, CreateClient());

    flight::FlightCallOptions call_options;
    ARROW_ASSIGN_OR_RAISE(std::unique_ptr<flight::FlightInfo> tables, client->GetTables(call_options, NULL, NULL, NULL, NULL, NULL));

    if (tables != nullptr) {
        ARROW_RETURN_NOT_OK(printResults(tables, client, call_options));
    }

    client->Execute(call_options, "SELECT * FROM LINEITEM LIMIT 10");

    // runQueries(client, query_path, skip_queries, call_options);

    // // std::shared_ptr<arrow::flight::sql::duckdbflight::DuckDBFlightSqlServer> server;
    // ARROW_ASSIGN_OR_RAISE(auto server,
    //                         arrow::flight::sql::duckdbflight::DuckDBFlightSqlServer::Create(
    //                             db_path.c_str(),
    //                             nullptr
    //                         )
    // );

    return arrow::Status::OK();
}

int main(int argc, char** argv) {
    auto status = Main();
    if (!status.ok()) {
        std::cerr << status << std::endl;
        return 1;
    }

    return EXIT_SUCCESS;
}