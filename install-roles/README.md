# Fusion installation roles

This directory contains the minimal role and clusterRole that must be assigned to
a user in order to install fusion 5 with helm v3.

First, use the `customize_fusion_values.sh` script for creating your fusion values yaml file.

To use these role in a cluster, as an admin user first create the namespace that you wish to
install fusion into and label it for seldon's use:

```
k create namespace fusion-namespace
k label namespace fusion-namespace seldon.io/controller-id=fusion-namespace
```

Install the required CRDs as an admin user, for this we are going to download the fusion chart:

```
helm fetch lucidworks/fusion --version <fusion-version> --untar
find . -iname crds -type d -exec kubectl apply -f {} \;
```

Apply the `role.yaml` and `cluster-role.yaml` files to that namespace

```
k apply -f cluster-role.yaml
k apply -f --namespace fusion-namespace role.yaml
```

Then bind the rolebinding and clusterolebinding to the install user:

```
k create --namespace fusion-namespace rolebinding fusion-install-rolebinding --role fusion-installer --user <install_user>
k create clusterrolebinding fusion-install-rolebinding --clusterrole fusion-installer --user <install_user>
```

After this changes are applied, some extra steps need to be performed:

* Update your fusion values yaml file and add the following values to the required services:

    ```
    query-pipeline:
      useAvailabilityZoneRouting: false

    solr:
      setAvailabilityZone: false

    rpc-service:
      plugins:
        crd:
          create: false

    argo:
      createAggregateRoles: false

    ml-model-service:
      runLabelNamespaceJob: false
    ```

* Modify your upgrade fusion script and add `--skip-crds` to the helm command.

* Use your upgrade fusion script for installing fusion with your `<install_user>`.
