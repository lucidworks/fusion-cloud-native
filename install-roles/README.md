# Fusion installation roles

This directory contains the minimal role and clusterRole that must be assigned to
a user in order to install fusion 5 with helm v3.

To use these role in a cluster, as an admin user first create the namespace that you wish to
install fusion into:
```
k create namespace fusion-namespace
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

You will then be able to run the `helm install` command as the `<install_user>`
