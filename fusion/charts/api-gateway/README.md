# Deployment

## Secrets

This helm chart requires you to create a secret with the name of: `okta-client-secret`
in the namespace that you are deploying the application. This can be created with:

```
kubectl create secret generic okta-client-secret --from-literal=secret=<your_okta_client_secret>
```
