# OpenChoreo 1.1.2 environment boundary

This directory uses only APIs served by the installed OpenChoreo 1.1.2 control plane.

- `DeploymentPipeline` expresses the Development to Staging to Production promotion topology.
- `Environment.spec.isProduction: true` marks Production. Version 1.1.2 has no declarative manual-approval or auto-promotion fields, so promotion remains an explicit release operation.
- The data-plane controller creates the workload cell namespaces when a project is reconciled. Secrets remain namespace-scoped and are never copied into Git.
- The installed release does not serve `ClusterProjectType`; namespace quotas, service accounts, and baseline NetworkPolicies must therefore be attached after cell namespace creation or after upgrading OpenChoreo to a release that supports project templates.
