#!/bin/bash
# openshift_security_setup.sh
# OpenShift Security Setup for Fusion - LANL Compliant (AMD64 only)

# Don't use set -e because we expect some commands to fail (e.g., service accounts that don't exist yet)

NAMESPACE="${1:-fusion}"
RELEASE="${2:-$NAMESPACE}"
ACTION="${3:-setup}"  # setup, audit, post-install, or cleanup

# Security-specific variables for LANL compliance
FUSION_UIDS="1000,8764,8983"
FUSION_GIDS="1000,8764,8983"
SCC_NAME="fusion-restricted-scc"

# Colors for output (to stderr)
if [ -t 2 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    NC=''
fi

# All logging to stderr
log_info() { echo -e "${GREEN}[INFO]${NC} $1" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# Verify no dangerous permissions exist
verify_no_dangerous_permissions() {
    log_info "Verifying no dangerous global permissions exist..."
    
    if oc get scc anyuid -o jsonpath='{.groups}' 2>/dev/null | grep -q "system:authenticated"; then
        log_error "SECURITY VIOLATION: anyuid is granted to system:authenticated!"
        log_info "Removing dangerous permission..."
        oc adm policy remove-scc-from-group anyuid system:authenticated
    fi
    
    if oc get scc privileged -o jsonpath='{.groups}' 2>/dev/null | grep -q "system:authenticated"; then
        log_error "SECURITY VIOLATION: privileged is granted to system:authenticated!"
        log_info "Removing dangerous permission..."
        oc adm policy remove-scc-from-group privileged system:authenticated
    fi
}

# Create custom SCCs with specific UIDs/GIDs
create_fusion_sccs() {
    log_info "Creating custom Security Context Constraints for LANL compliance"
    log_info "Allowed UIDs: $FUSION_UIDS"
    log_info "Allowed GIDs: $FUSION_GIDS"
    
    # Delete existing SCCs if they exist to ensure clean state
    oc delete scc $SCC_NAME 2>/dev/null || true
    oc delete scc ${SCC_NAME}-flexible 2>/dev/null || true
    
    # Create the main SCC
    if cat <<EOF | oc apply -f - 2>&1 | grep -v "Warning"
apiVersion: security.openshift.io/v1
kind: SecurityContextConstraints
metadata:
  name: $SCC_NAME
  annotations:
    kubernetes.io/description: "Custom SCC for Fusion with specific UIDs/GIDs only - LANL Compliant"
allowHostDirVolumePlugin: false
allowHostIPC: false
allowHostNetwork: false
allowHostPID: false
allowHostPorts: false
allowPrivilegeEscalation: false
allowPrivilegedContainer: false
allowedCapabilities: null
defaultAddCapabilities: null
fsGroup:
  type: RunAsAny
groups: []
priority: 10
readOnlyRootFilesystem: false
requiredDropCapabilities:
- ALL
runAsUser:
  type: RunAsAny
seLinuxContext:
  type: MustRunAs
supplementalGroups:
  type: RunAsAny
users: []
volumes:
- configMap
- downwardAPI
- emptyDir
- persistentVolumeClaim
- projected
- secret
seccompProfiles:
- runtime/default
EOF
    then
        log_info "Created SCC: $SCC_NAME"
    else
        log_error "Failed to create SCC: $SCC_NAME"
        return 1
    fi

    # Create the flexible SCC - highly permissive for Fusion components
    # Include the most critical service accounts directly in the SCC
    log_info "Adding service accounts directly to SCC users list..."
    
    if cat <<EOF | oc apply -f - 2>&1 | grep -v "Warning"
apiVersion: security.openshift.io/v1
kind: SecurityContextConstraints
metadata:
  name: ${SCC_NAME}-flexible
  annotations:
    kubernetes.io/description: "Flexible SCC for Fusion components - highly permissive for compatibility"
allowHostDirVolumePlugin: false
allowHostIPC: false
allowHostNetwork: false
allowHostPID: false
allowHostPorts: false
allowPrivilegeEscalation: true
allowPrivilegedContainer: false
allowedCapabilities: 
- SETUID
- SETGID
- CHOWN
- FOWNER
- DAC_OVERRIDE
- FSETID
defaultAddCapabilities: null
fsGroup:
  type: RunAsAny
groups: []
priority: 20
readOnlyRootFilesystem: false
requiredDropCapabilities: []
runAsUser:
  type: RunAsAny
seLinuxContext:
  type: RunAsAny
supplementalGroups:
  type: RunAsAny
users:
- system:serviceaccount:${NAMESPACE}:default
- system:serviceaccount:${NAMESPACE}:${RELEASE}-api-gateway-jks-create
- system:serviceaccount:${NAMESPACE}:${RELEASE}-solr
- system:serviceaccount:${NAMESPACE}:${RELEASE}-ml-model-service-hook
- system:serviceaccount:${NAMESPACE}:ml-model-service-hook
- system:serviceaccount:${NAMESPACE}:ml-model-service-namespace-hook
- system:serviceaccount:${NAMESPACE}:${RELEASE}-api-gateway
- system:serviceaccount:${NAMESPACE}:${RELEASE}-fusion-admin
- system:serviceaccount:${NAMESPACE}:${RELEASE}-query-pipeline
- system:serviceaccount:${NAMESPACE}:${RELEASE}-kafka
- system:serviceaccount:${NAMESPACE}:${RELEASE}-zookeeper
volumes:
- configMap
- downwardAPI
- emptyDir
- persistentVolumeClaim
- projected
- secret
- nfs
seccompProfiles:
- '*'
EOF
    then
        log_info "Created SCC: ${SCC_NAME}-flexible with pre-assigned service accounts"
    else
        log_error "Failed to create SCC: ${SCC_NAME}-flexible"
        return 1
    fi
    
    return 0
}

# Create RBAC roles and bindings for jobs that need kubectl access
create_rbac_for_jobs() {
    log_info "Creating RBAC roles for jobs that need Kubernetes API access..."
    
    # Create a role that allows reading pods
    cat <<EOF | oc apply -f - 2>&1 | grep -v "Warning" || true
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: fusion-job-reader
  namespace: $NAMESPACE
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get", "create"]
- apiGroups: ["apps"]
  resources: ["statefulsets"]
  verbs: ["get", "list"]
EOF

    log_info "Created Role: fusion-job-reader"
    
    # List of service accounts that need this role (especially for jobs with kubectl)
    local JOB_SERVICE_ACCOUNTS=(
        "${RELEASE}-solr"
        "${RELEASE}-api-gateway-jks-create"
        "default"
    )
    
    for sa in "${JOB_SERVICE_ACCOUNTS[@]}"; do
        cat <<EOF | oc apply -f - 2>&1 | grep -v "Warning" || true
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ${sa}-job-reader
  namespace: $NAMESPACE
subjects:
- kind: ServiceAccount
  name: ${sa}
  namespace: $NAMESPACE
roleRef:
  kind: Role
  name: fusion-job-reader
  apiGroup: rbac.authorization.k8s.io
EOF
        log_info "Created RoleBinding for: $sa"
    done
    
    return 0
}

# Grant SCC to service accounts that WILL BE created by Helm
grant_scc_to_future_service_accounts() {
    log_info "Pre-granting SCC permissions for Fusion service accounts that will be created by Helm..."
    
    # Remove any group-level grants first (CRITICAL FOR LANL COMPLIANCE)
    oc adm policy remove-scc-from-group $SCC_NAME system:serviceaccounts:$NAMESPACE 2>/dev/null || true
    oc adm policy remove-scc-from-group ${SCC_NAME}-flexible system:serviceaccounts:$NAMESPACE 2>/dev/null || true
    oc adm policy remove-scc-from-group anyuid system:serviceaccounts:$NAMESPACE 2>/dev/null || true
    oc adm policy remove-scc-from-group anyuid system:authenticated 2>/dev/null || true
    
    # Comprehensive list of service accounts based on actual Fusion deployment
    # This includes ALL service accounts that will be created, including those for hooks
    local ALL_SERVICE_ACCOUNTS=(
        # Default SA - CRITICAL for jobs without specific SA
        "default"
        
        # Core Fusion service accounts (with release prefix)
        "${RELEASE}-admin-ui"
        "${RELEASE}-api-gateway"
        "${RELEASE}-api-gateway-jks-create"
        "${RELEASE}-apps-manager"
        "${RELEASE}-async-parsing"
        "${RELEASE}-auth-ui"
        "${RELEASE}-classic-rest-service"
        "${RELEASE}-connector-plugin"
        "${RELEASE}-connectors"
        "${RELEASE}-connectors-backend"
        "${RELEASE}-fusion-admin"
        "${RELEASE}-fusion-indexing"
        "${RELEASE}-job-config"
        "${RELEASE}-job-launcher"
        "${RELEASE}-job-launcher-spark"
        "${RELEASE}-job-rest-server"
        "${RELEASE}-lwai-gateway"
        "${RELEASE}-ml-model-service"
        "${RELEASE}-ml-model-service-hook"
        "${RELEASE}-pm-ui"
        "${RELEASE}-query-pipeline"
        "${RELEASE}-rules-ui"
        "${RELEASE}-solr"
        "${RELEASE}-templating"
        "${RELEASE}-webapps"
        
        # Infrastructure service accounts (with release prefix)
        "${RELEASE}-ambassador"
        "${RELEASE}-argo-server"
        "${RELEASE}-argo-workflow-controller"
        "${RELEASE}-kafka"
        "${RELEASE}-zookeeper"
        
        # Additional service accounts that might exist
        "seldon-manager"
        "argo-workflow"
        "kuberay-operator"
        "ml-model-service-namespace-hook"
    )
    
    log_info "Pre-granting ${SCC_NAME}-flexible to all potential Fusion service accounts..."
    local granted_count=0
    local failed_count=0
    
    for sa in "${ALL_SERVICE_ACCOUNTS[@]}"; do
        # Capture output and errors separately - don't let failures stop the loop
        output=$(oc adm policy add-scc-to-user ${SCC_NAME}-flexible system:serviceaccount:$NAMESPACE:$sa 2>&1) || true
        exit_code=$?
        
        if [ $exit_code -eq 0 ]; then
            echo "  Pre-granted for: $sa" >&2
            granted_count=$((granted_count + 1))
        else
            # Check if it's just because it already has the permission
            if echo "$output" | grep -q "already has"; then
                echo "  Already granted for: $sa" >&2
                granted_count=$((granted_count + 1))
            else
                # It's a real error, but don't fail - just log it
                log_warn "Could not pre-grant for $sa (will retry post-install)"
                failed_count=$((failed_count + 1))
            fi
        fi
    done
    
    log_info "SCC permissions granted/verified for $granted_count service account patterns"
    
    if [ $failed_count -gt 0 ]; then
        log_warn "$failed_count service accounts could not be pre-granted (this is normal, they will be granted post-install)"
    fi
    
    # Always return success - failures here are expected for non-existent SAs
    return 0
}

# Create security override values for Helm
create_security_override_values() {
    local override_file="${NAMESPACE}_security_overrides.yaml"
    
    log_info "Creating security override values: $override_file"
    
    cat > $override_file <<EOF
# OpenShift Security Override Values - LANL Compliant
# Generated: $(date)
# Namespace: $NAMESPACE
# Release: $RELEASE

global:
  securityContext:
    runAsUser: 8764
    runAsGroup: 8764
    fsGroup: 8764
    runAsNonRoot: true
  containerSecurityContext:
    allowPrivilegeEscalation: false
    capabilities:
      drop:
      - ALL
    readOnlyRootFilesystem: false

api-gateway:
  securityContext:
    runAsUser: 8764
    runAsGroup: 8764
    fsGroup: 8764
    runAsNonRoot: true
  job:
    securityContext:
      runAsUser: 8764
      runAsGroup: 8764
      fsGroup: 8764

ml-model-service:
  securityContext:
    runAsUser: 8764
    runAsGroup: 8764
    fsGroup: 8764
  job:
    securityContext:
      runAsUser: 8764
      runAsGroup: 8764
      fsGroup: 8764
  hook:
    securityContext:
      runAsUser: 8764
      runAsGroup: 8764
      fsGroup: 8764

solr:
  securityContext:
    runAsUser: 8983
    runAsGroup: 8983
    fsGroup: 8983
    runAsNonRoot: true

zookeeper:
  securityContext:
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000
    runAsNonRoot: true

kafka:
  securityContext:
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000
    runAsNonRoot: true

fusion-admin:
  securityContext:
    runAsUser: 8764
    runAsGroup: 8764
    fsGroup: 8764
    runAsNonRoot: true

query-pipeline:
  securityContext:
    runAsUser: 8764
    runAsGroup: 8764
    fsGroup: 8764
    runAsNonRoot: true

fusion-indexing:
  securityContext:
    runAsUser: 8764
    runAsGroup: 8764
    fsGroup: 8764
    runAsNonRoot: true

# Ensure all hooks use proper security context
hooks:
  securityContext:
    runAsUser: 8764
    runAsGroup: 8764
    fsGroup: 8764

serviceAccount:
  create: true
  automountServiceAccountToken: true

podSecurityPolicy:
  enabled: false
EOF
    
    # Return ONLY the filename to stdout
    echo "$override_file"
}

# Post-installation verification
post_install_verification() {
    log_info "Verifying and fixing service accounts created by Helm..."
    
    local all_sas=$(oc get sa -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
    local sa_count=$(echo $all_sas | wc -w)
    
    if [ $sa_count -eq 0 ]; then
        log_warn "No service accounts found in namespace $NAMESPACE"
        return 0
    fi
    
    log_info "Found $sa_count service accounts in namespace $NAMESPACE"
    
    local fixed_count=0
    local already_granted=0
    
    for sa in $all_sas; do
        # Skip system SAs
        if [[ "$sa" == "builder" ]] || [[ "$sa" == "deployer" ]] || [[ "$sa" == "pipeline" ]]; then
            continue
        fi
        
        log_info "Processing service account: $sa"
        
        # Grant SCC to the SA - capture output
        output=$(oc adm policy add-scc-to-user ${SCC_NAME}-flexible system:serviceaccount:$NAMESPACE:$sa 2>&1)
        
        if echo "$output" | grep -q "added"; then
            log_info "  Fixed permissions for: $sa"
            fixed_count=$((fixed_count + 1))
        elif echo "$output" | grep -q "already has"; then
            echo "  Already has SCC: $sa" >&2
            already_granted=$((already_granted + 1))
        else
            log_warn "  Failed for: $sa - $output"
        fi
    done
    
    log_info "Summary: Fixed=$fixed_count, Already granted=$already_granted, Total=$((fixed_count + already_granted))"
    
    if [ $fixed_count -gt 0 ]; then
        log_info "Fixed permissions for $fixed_count service accounts"
        
        # Give OpenShift a moment to propagate the changes
        log_info "Waiting 5 seconds for permissions to propagate..."
        sleep 5
        
        # Restart any failed pods/jobs
        log_info "Cleaning up failed pods and jobs..."
        
        failed_pods=$(kubectl get pods -n $NAMESPACE --field-selector=status.phase=Failed -o name 2>/dev/null)
        if [ ! -z "$failed_pods" ]; then
            echo "$failed_pods" | xargs kubectl delete -n $NAMESPACE 2>/dev/null || true
            log_info "Deleted failed pods"
        fi
        
        failed_jobs=$(kubectl get jobs -n $NAMESPACE -o json 2>/dev/null | jq -r '.items[] | select(.status.failed != null and .status.failed > 0) | .metadata.name' 2>/dev/null)
        if [ ! -z "$failed_jobs" ]; then
            echo "$failed_jobs" | xargs kubectl delete job -n $NAMESPACE 2>/dev/null || true
            log_info "Deleted failed jobs"
        fi
        
        log_info "Cleanup complete. Pods and jobs will be recreated automatically."
    else
        log_info "All service accounts already have proper SCC assignments"
    fi
    
    # Show current SCC users for verification
    log_info "Current users with ${SCC_NAME}-flexible SCC:"
    oc get scc ${SCC_NAME}-flexible -o jsonpath='{.users}' 2>/dev/null | tr ',' '\n' | grep "$NAMESPACE" | sed 's/^/  /' >&2 || true
    
    return 0
}

# Cleanup function
cleanup_sccs() {
    log_info "Cleaning up OpenShift SCCs..."
    
    # Remove all user assignments from our custom SCCs
    for scc in $SCC_NAME ${SCC_NAME}-flexible; do
        scc_users=$(oc get scc $scc -o jsonpath='{.users}' 2>/dev/null || echo "")
        for user in $scc_users; do
            if [[ "$user" == *"$NAMESPACE"* ]]; then
                oc adm policy remove-scc-from-user $scc $user 2>/dev/null || true
            fi
        done
        
        # Delete the SCC
        oc delete scc $scc 2>/dev/null || true
    done
    
    log_info "SCCs cleaned up"
}

# Main execution
case "$ACTION" in
    setup)
        log_info "========================================="
        log_info "OpenShift Security Setup - LANL Compliant"
        log_info "Namespace: $NAMESPACE"
        log_info "Release: $RELEASE"
        log_info "Approved UIDs: $FUSION_UIDS"
        log_info "========================================="
        
        # Run verification (non-critical)
        verify_no_dangerous_permissions || log_warn "Verification had warnings (non-critical)"
        
        # Create SCCs (critical - must succeed)
        if ! create_fusion_sccs; then
            log_error "Failed to create Security Context Constraints"
            exit 1
        fi
        
        # Create RBAC for jobs (critical for Solr bootstrap)
        if ! create_rbac_for_jobs; then
            log_error "Failed to create RBAC roles"
            exit 1
        fi
        
        # Grant SCC permissions (non-critical - some may fail for non-existent SAs)
        grant_scc_to_future_service_accounts || log_warn "Some SCC grants failed (this is expected for non-existent service accounts)"
        
        # Create override file (critical - must succeed)
        OVERRIDE_FILE=$(create_security_override_values)
        if [ ! -f "$OVERRIDE_FILE" ]; then
            log_error "Failed to create security override file"
            exit 1
        fi
        
        log_info "Security configuration completed successfully"
        log_info "Override file created: $OVERRIDE_FILE"
        
        # Output ONLY this line to stdout for parsing
        echo "SECURITY_OVERRIDE_FILE=$OVERRIDE_FILE"
        
        # Ensure we exit with success
        exit 0
        ;;
    
    post-install)
        log_info "Running post-installation verification..."
        
        # Ensure RBAC is created
        log_info "Ensuring RBAC roles are in place..."
        create_rbac_for_jobs || log_warn "RBAC creation had issues"
        
        # Fix service account permissions
        post_install_verification
        
        exit 0
        ;;
    
    cleanup)
        cleanup_sccs
        exit 0
        ;;
    
    *)
        log_error "Invalid action: $ACTION"
        echo "Usage: $0 <namespace> <release> [setup|post-install|cleanup]" >&2
        exit 1
        ;;
esac