# Arrow Flight SQL server - DuckDB

## Description

This repo is a reduced version of [flight-sql-server-example](https://github.com/voltrondata/flight-sql-server-example). Several adjustments were made, but the majority of the original code remains, hopefully I will be able to keep it up-to-date with upstream.

- The mandatory TLS was removed (authentication was removed as well since my C++ skills are poor), since this will be deployed in a Kubernetes cluster the lack of encryption and access control will be replaced by strict `NetworkPolicies` and a CNI with enable encryption.
- The container image is signficantly smaller and does not include test data and python stuff.
- Random utils, entrypoints and other miscellaneous files were reduced.

Overall the target environment is a Kubernetes cluster with Grafana [FlightSQL client](https://grafana.com/grafana/plugins/influxdata-flightsql-datasource/), which automatically loads the provided DuckDB schema from an S3 object storage (e.g. MinIO).

## Example

```yaml
---

apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: flight

spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: flight
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: monitoring
          podSelector:
            matchLabels:
              app.kubernetes.io/name: grafana
      ports:
        - protocol: TCP
          port: 31337

---

apiVersion: v1
kind: Service
metadata:
  name: flight

spec:
  selector:
    app.kubernetes.io/name: flight
  ports:
    - name: sql
      port: 31337

--- 

apiVersion: apps/v1
kind: Deployment
metadata:
  name: flight

spec:
  revisionHistoryLimit: 3
  selector:
    matchLabels:
      app.kubernetes.io/name: flight
  template:
    metadata:
      labels:
        app.kubernetes.io/name: flight
    spec:
      automountServiceAccountToken: true
      securityContext:
        fsGroup: 1000
      initContainers:
        - name: flight-init
          image: gitea.example.home.arpa/infrastructure/code:v1
          command: [ /bin/bash, -c ]
          args:
            - duckdb --init sql/schema.sql /data/duck.db "SHOW TABLES;";
            - chmod 0666 /data/duck.db
          envFrom:
            - secretRef:
                name: argo-env-creds
          volumeMounts:
            - name: data
              mountPath: /data
      containers:
        - name: flight
          image: gitea.example.home.arpa/infrastructure/flightsql:v1
          resources:
            requests:
              cpu: 50m
              memory: 128Mi
          ports:
            - name: sql
              containerPort: 31337
          envFrom:
            - secretRef:
                name: argo-env-creds
          volumeMounts:
            - name: data
              mountPath: /data
      volumes:
        - name: data
          emptyDir: {}
```
