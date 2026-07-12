#!/usr/bin/env bash
set -euo pipefail

namespace="${OPENCHOREO_NAMESPACE:-openchoreo-control-plane}"

kubectl -n "$namespace" patch deployment backstage --type=strategic --patch '{
  "spec": {
    "strategy": {"type": "Recreate", "rollingUpdate": null},
    "template": {
      "spec": {
        "containers": [{
          "name": "backstage",
          "livenessProbe": {
            "initialDelaySeconds": 600,
            "periodSeconds": 10,
            "timeoutSeconds": 5,
            "failureThreshold": 6
          },
          "readinessProbe": {
            "initialDelaySeconds": 10,
            "periodSeconds": 5,
            "timeoutSeconds": 5,
            "failureThreshold": 120
          }
        }]
      }
    }
  }
}'

kubectl -n "$namespace" rollout status deployment/backstage --timeout=15m
