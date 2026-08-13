# Fusion Cloud Native

The customer-facing install kit for Fusion 5 on Kubernetes. **There is no application code here** —
this repo is Bash scripts, Helm values templates, Grafana dashboards and AsciiDoc. Its job is to
take an operator from an empty cloud account to a running Fusion cluster, and to leave them holding
a values file and an upgrade script they can keep in version control.

**Default branch is `master`**, not `main`. Confirm with `git ls-remote --symref origin HEAD` rather
than assuming.

Two things shape everything below. First, **the README is a published document** — it is the source
for the Fusion documentation site, and edits inside its tag regions go out to customers. Second,
**there is no CI here at all**: no GitHub Actions, no Jenkinsfile, no shellcheck, no test. Nothing
catches a broken script except an operator running it against a real cloud account.

## Compatibility Constraints

There is no dependency manifest. The versions that matter are:

- **`CHART_VERSION`** — the Fusion Helm chart to install. It is declared as a literal in **five
  scripts**: `setup_f5_k8s.sh`, `setup_f5_gke.sh`, `setup_f5_eks.sh`, `setup_f5_aks.sh` and
  `customize_fusion_values.sh`. Read the current value from any of them; a release bump must change
  all five. `upgrade_fusion.sh.example` takes it as a `<CHART_VERSION>` placeholder, so it needs no
  edit. **Missing one of the five is the standard mistake** — the four setup scripts each pass
  `--version` down to `customize_fusion_values.sh`, so a stale value in `customize` only surfaces
  when someone runs it directly.
- **Helm 3.** `setup_f5_k8s.sh` greps `helm version --short` for `v3` and prints a warning if it
  does not match — it does not exit. The README states the minimum; nothing enforces it.
- **`kubectl`, and one of `gcloud` / `eksctl` + `aws` / `az`** depending on the provider script.
- The bundled subcharts under `monitoring/helm/*/charts/` are **committed `.tgz` files**, not
  fetched at install time. Upgrading Grafana, Prometheus, Loki or Promtail means replacing the
  tarball and the matching entry in `requirements.yaml` / `requirements.lock` together — and both
  `fusion-monitoring` and `fusion-monitoring-stack` carry their own copies.

## Gotchas

Things that have cost time before, or that reading the code alone will not tell you.

### Every `sed` substitution exists twice, once per platform

`customize_fusion_values.sh` branches on `$OSTYPE` for **every single replacement**, because GNU
`sed` wants `-i -e` and BSD `sed` wants `-i '' -e`:

```bash
if [[ "$OSTYPE" == "linux-gnu" || "$OSTYPE" == "msys" ]]; then
  sed -i    -e "s|{NODE_POOL}|${NODE_POOL}|g" "$MY_VALUES"
else
  sed -i '' -e "s|{NODE_POOL}|${NODE_POOL}|g" "$MY_VALUES"
fi
```

**Adding a placeholder means adding it to both branches.** Miss one and the script works on your
machine and silently leaves a literal `{PLACEHOLDER}` in the generated YAML on everyone else's —
Helm will often accept that as a string rather than failing, so the mistake reaches a cluster.

Note also that the `$OSTYPE` test is a whitelist of two values. Anything else — including
`linux-musl` and some container shells — falls into the BSD branch and fails on GNU `sed`.

### Two placeholder syntaxes, deliberately

`customize_fusion_values.yaml.example` uses `{BRACES}`; `upgrade_fusion.sh.example` uses
`<ANGLE_BRACKETS>`. Same script substitutes both. Use the convention of the file you are editing.

### `customize_fusion_values.sh` must be run from the repo root

It copies its inputs by **relative path** — `cp customize_fusion_values.yaml.example …`,
`cp example-values/monitoring-values.yaml …`, `cp upgrade_fusion.sh.example …` — and contains no
`SCRIPT_DIR` at all. `setup_f5_k8s.sh` does use `SCRIPT_DIR` and can be invoked from anywhere. The
two behave differently; do not assume from one what the other does.

### `setup_f5_aks.sh` sources the shared script, on both of its paths

GKE and EKS invoke the shared script in a subshell with an absolute path
(`( "${SCRIPT_DIR}/setup_f5_k8s.sh" … )`). AKS instead uses `source ./setup_f5_k8s.sh` — same shell,
**relative path** — for *both* its install path and its purge path. So:

- **AKS only works when run from the repo directory**, install as well as purge.
- The shared script's variables and functions leak back into the AKS script after the call.

If you are changing `setup_f5_k8s.sh`, check the AKS path separately; it is not equivalent to the
other two.

### The setup scripts and the customize script disagree on defaults

`setup_f5_k8s.sh` defaults to one Solr pod, one Kafka pod and provider `k8s`.
`customize_fusion_values.sh` defaults to **three** Solr pods, **three** Kafka pods and provider
`gke`. Going through a setup script gets you the former (it passes its own values down explicitly);
running `customize_fusion_values.sh` by hand gets you the latter. Both paths are documented in the
README, which is how people end up surprised. `NODE_POOL` differs too — `"{}"` versus `""`.

`ZK_REPLICAS=3` is hardcoded in `customize_fusion_values.sh` with no flag at all.

### The Kafka bootstrap URL assumes exactly one or exactly three brokers

```bash
if [[ "$KAFKA_REPLICAS" == 1 ]]; then
  KAFKA_URL="$RELEASE-kafka-headless:9092"
else
  KAFKA_URL="…kafka-0…,…kafka-1…,…kafka-2…"
fi
```

`--num-kafka 2` produces a URL naming a broker that will never exist; `--num-kafka 5` produces one
that ignores brokers 3 and 4. Neither is validated. Fix the generation rather than the symptom if
you touch this.

### Re-running setup with different flags does nothing

If the generated `<provider>_<cluster>_<release>_fusion_values.yaml` already exists,
`setup_f5_k8s.sh` prints *"Values file … already exists, not regenerating"* and carries on with the
old file. And on a non-upgrade run, an existing upgrade script is a **hard exit 1** (*"Please use a
new release name or upgrade your current release"*).

So the flags on the command line are only honoured on the very first run for a given
provider/cluster/release triple. After that, edit the values file or delete it. This is intentional
— the generated file is the operator's to own — but it reads as the script ignoring you.

### There is a silent-degradation fallback if `customize_fusion_values.sh` is absent

`setup_f5_k8s.sh` checks `-f "${SCRIPT_DIR}/customize_fusion_values.sh"` and, if it is missing,
heredocs a **minimal** values file inline (Solr replicas, Solr disk size, Kafka replicas, Prometheus
on/off) and a bare-bones upgrade script. No node pool, no ingress, no TLS, no monitoring values,
none of the `example-values/` overlays. It warns, but it does not fail.

In a git clone the script is always there. The fallback bites people who copy a single setup script
into their own tooling — they get an install that looks successful and is configured differently
from every documented one.

### The two generated upgrade scripts treat arguments in opposite ways

`upgrade_fusion.sh.example` — the normal path — turns **any** first argument into a dry run:

```bash
DRY_RUN_REQUESTED="${1:-}"
if [ ! -z "${DRY_RUN_REQUESTED}" ]; then
  DRY_RUN="--dry-run"
fi
```

`--values extra.yaml`, `-n prod`, a typo — all of them produce a run that reports success and
changes nothing. Extra values files go in the `MY_VALUES` variable *inside* the script, which is
what the `# TODO: append more --values <file> args here` comment is telling you.

The fallback script from the previous gotcha does the opposite: it ends in `\$@`, passing every
argument straight through to `helm upgrade`. Same filename convention, inverted contract.

The normal script also **changes your kubectl default namespace** on the way out
(`kubectl config set-context --current --namespace=…`). Expect your shell to be pointed somewhere
new after an upgrade.

### Namespace ownership is advisory, and derived differently in each script

`setup_f5_k8s.sh` labels the namespace `owner=<value>` and refuses to upgrade or purge a namespace
whose label does not match, unless `--force` is passed. Where the value comes from is not uniform:

| Script | GKE | Everything else |
|---|---|---|
| `setup_f5_k8s.sh` | `gcloud auth list` active account, `@` → `-` | falls back to `$USER`, then `unknown` |
| generated upgrade script | same `gcloud` derivation | empty — **no owner label is applied at all** |

So the guard is weakest exactly where it is most likely to matter: in CI or any shell with `$USER`
unset, every non-GKE install is `unknown` and the check is a no-op. Treat it as a courtesy, not a
safety mechanism, and do not add a feature that depends on it.

**`--purge` is irreversible** and says so in its own usage text. Never add it to an example.

### `migrations/README.adoc` opens with a version claim that is years stale

Its first line says *"The latest version of Fusion 5 is 5.3.x"* while the main README's release
table runs far past that. The migration *steps* below it are still the ones customers follow. Fix
the sentence if you are in there; do not treat it as evidence of which migrations are current.

### The `mcp/` bundles are undocumented but are a per-release artefact

`mcp/*.mcpb` are committed, one per Fusion release, each landing in its own PR — and they are
referenced **nowhere** in the README or any other doc in the repo. Nothing in the release checklist
mentions them, so they are easy to forget on a version bump. Find out who consumes them before
touching or removing them.

### The release table covers more than one live line

`README.adoc`'s release table interleaves the current line with the older maintained one, newest
first by date rather than grouped by line. When adding a row, place it by date and check you have
not implied a version supersedes one it does not.

## Conventions and Preferences

- **Bash, targeting both macOS and Linux.** Every `sed -i` needs the `$OSTYPE` branch; prefer adding
  to the existing branch pair over introducing a third path.
- **Prefer generating a values file over adding a flag.** The design of this repo is that the
  scripts produce artefacts the operator keeps and edits — `<provider>_<cluster>_<release>_*.yaml`
  and the matching upgrade script. New configuration should land as a template placeholder or an
  `example-values/` overlay, not as another command-line option threaded through five scripts.
- **Prefer `example-values/*.yaml` overlays** for optional configuration. `--values` can be passed
  repeatedly and `customize_fusion_values.sh` wires each one into the generated upgrade script.
- **Keep the four provider scripts thin.** Cluster creation and cloud-specific setup belong in
  `setup_f5_<provider>.sh`; everything Kubernetes-generic belongs in `setup_f5_k8s.sh`, which they
  all delegate to.
- **Prefer an absolute `${SCRIPT_DIR}` subshell call over `source` with a relative path** when one
  script invokes another — GKE and EKS get this right, AKS does not.
- **Never commit a generated file.** `<provider>_<cluster>_<release>_fusion_values.yaml`,
  `*_upgrade_fusion.sh` and `*_monitoring_values.yaml` are operator artefacts, and running the
  scripts drops them in the repo root where they are easy to `git add` by accident. Only the
  `.example` templates belong in git.
- Print errors to the user and `exit 1`; there is no logging framework and no test suite, so the
  usage text and the error messages are the interface.

## Architecture

Four entry points, one shared core:

```
setup_f5_gke.sh ─┐
setup_f5_eks.sh ─┼─► setup_f5_k8s.sh ─► customize_fusion_values.sh ─► <values>.yaml
setup_f5_aks.sh ─┤     (namespace,          (template substitution)     <upgrade>.sh
(direct k8s) ────┘      helm repo,
                        helm upgrade)
```

The provider scripts create or validate a cluster with `gcloud` / `eksctl` / `az`, then hand off.
`setup_f5_k8s.sh` owns the namespace, the ownership label, the Helm repo, the values generation and
the `helm upgrade --install`. `customize_fusion_values.sh` does pure text substitution on
`customize_fusion_values.yaml.example` and `upgrade_fusion.sh.example`.

Supporting material:

- **`example-values/`** — optional overlays passed with `--values` and recorded in the generated
  upgrade script: resources, affinity, replicas, monitoring, Grafana, Prometheus, and
  version-specific `repository*.yaml` variants for older Fusion lines.
- **`monitoring/`** — Grafana dashboards as JSON plus two Helm charts. `fusion-monitoring-stack`
  bundles Grafana, Prometheus, Loki and Promtail as committed tarballs; `fusion-monitoring` is the
  lighter one (Grafana + Prometheus). Dashboards come in current and `-545` variants for older
  Fusion versions.
- **`install-roles/`** — the minimum RBAC role and cluster role for installing without cluster-admin.
- **`gatling-qps/`** — a Scala/Maven Gatling load-test harness, self-contained and built separately.
- **`jwt-client-example/`** — a small Gradle sample showing JWT auth against the gateway.
- **`mcp/`** — per-release `.mcpb` bundles; see the gotcha above.
- **`additional_environments/`**, and the standalone `*.sh` utilities at the root (`install_prom.sh`,
  `purge_zk_logs.sh`, `set_initial_admin_pass.sh`, `update_*.sh` — `update_policy.sh` reads the
  root `policy.json` — `openshift_security_setup.sh`, `setup_gke_filestore.sh`,
  `gke_scale_namespace_up_or_down.sh`) — one-off operator tools, each independent of the install
  flow.

## Further Reading

- **`README.adoc`** — this is the product, not a developer note. Read it before changing any script,
  because the script's usage text and the README's instructions have to stay in agreement. It
  carries ~17 AsciiDoc tag regions (`// tag::body[]`, `// tag::releases[]`, `// tag::gke[]`,
  `// tag::upgrade-eks[]`, …) that are **included into the published Lucidworks documentation** — an
  edit inside a tagged region is a customer-facing docs change, so treat it as one.
- **`survival_guide/`** — read when you need the operational model rather than the install steps:
  `1_concepts.adoc` for how Fusion maps onto Kubernetes objects, `2_planning.adoc` for sizing and
  node-pool decisions, `3_operations.adoc` for day-two work. Also tagged for publication.
- **`migrations/README.adoc`** — read before changing anything that affects upgrade paths,
  especially the Solr 8→9 steps. Ignore its stale opening version claim.
- **`monitoring/helm/README.adoc`** and **`monitoring/grafana/README.adoc`** — read when adding or
  changing a dashboard, to see which chart consumes it and how the `-545` variants are selected.
- **`install-roles/README.md`** — read when a customer reports a permissions failure during install.
- **`gatling-qps/README.md`** — read only if you are running load tests; it is a separate build with
  its own toolchain.

## Reminders

### When Releasing a New Chart Version
- Update `CHART_VERSION` in all five scripts — the four `setup_f5_*.sh` and
  `customize_fusion_values.sh`
- Add a row to the release table in `README.adoc`, placed by date, with the release-notes link
- Add the matching `mcp/fusion-<version>.mcpb` bundle — nothing else in the repo will remind you
- Check whether `example-values/repository*.yaml` needs a new variant

### When Changing a Script
- Nothing lints or tests this repo; run the script end-to-end against a scratch cluster
- Any new `sed -i` needs both `$OSTYPE` branches
- Any new placeholder needs a matching substitution, or it ships as a literal into a customer's
  values file
- Changes to `setup_f5_k8s.sh` need a separate check against `setup_f5_aks.sh`, which `source`s it
- Keep the usage text in sync — it is the only reference an operator has at the prompt

### When Adding Configuration
- Prefer a placeholder in `customize_fusion_values.yaml.example` or a new `example-values/` overlay
  over a new flag
- If it must be a flag, thread it through the provider scripts *and* `setup_f5_k8s.sh` *and*
  `customize_fusion_values.sh`, and check the two sets of defaults still make sense together
- Make sure it survives into the generated upgrade script; configuration that only applies at
  install time silently disappears on the operator's next upgrade
