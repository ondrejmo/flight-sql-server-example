# Arrow Flight SQL server - DuckDB

## Description

This repo is a reduced version of [flight-sql-server-example](https://github.com/voltrondata/flight-sql-server-example). Several adjustments were made, but the majority of the original code remains, hopefully I will be able to keep it up-to-date with upstream.

- The mandatory TLS was removed (authentication was removed as well since my C++ skills are poor), since this will be deployed in a Kubernetes cluster the lack of encryption and access control will be replaced by strict `NetworkPolicies` and a CNI with enable encryption.
- The container image is signficantly smaller and does not include test data and python stuff.
- Random utils, entrypoints and other miscellaneous files were reduced.

Overall the target environment is a Kubernetes cluster with Grafana [FlightSQL client](https://grafana.com/grafana/plugins/influxdata-flightsql-datasource/), which automatically loads the provided DuckDB schema from an S3 object storage (e.g. MinIO).

## Example

```yaml
TBD
```
