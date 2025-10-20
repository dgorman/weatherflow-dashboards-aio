# Argo Workflow Deployment Setup - Summary

## What Was Created

This document summarizes the Argo Workflow deployment setup for weatherflow-collector, following the same pattern as solardashboard.

### New Files Created

1. **`argo/weatherflow-collector-deploy.yaml`**
   - Complete Argo Workflow definition with 4 steps
   - Clones from GitHub (not local rsync)
   - Builds with Docker-in-Docker
   - Tags images with git SHA
   - Deploys to Kubernetes

2. **`argo/trigger-deploy.sh`**
   - Helper script to submit the workflow
   - Works from local machine or production server
   - Provides monitoring commands

3. **`argo/README.md`**
   - Comprehensive workflow documentation
   - Usage instructions
   - Troubleshooting guide
   - Comparison with legacy deploy.sh

### Updated Files

1. **`DEPLOYMENT.md`**
   - Updated to emphasize Argo Workflow as primary method
   - Added git-based workflow documentation
   - Removed references to deprecated deploy.sh and setup.sh

## How It Works (Git-Based CI/CD)

### Workflow Steps

```
1. Git Clone (alpine/git)
   └─> Clones dgorman/weatherflow-dashboards-aio from GitHub
   └─> Records git SHA to /src/GIT_SHA

2. Docker Build (docker:20.10-dind)
   └─> Builds registry.olympusdrive.com/weatherflow-collector
   └─> Tags: latest + <git-sha>

3. Docker Push (docker:20.10-dind)
   └─> Pushes both tags to registry

4. Kubernetes Deploy (bitnami/kubectl)
   └─> Updates kustomization.yaml with git SHA tag
   └─> Applies manifests: kubectl apply -k k8s/overlays/prod
   └─> Triggers rollout: kubectl rollout restart
   └─> Waits for success (300s timeout)
```

## Recommended Workflow

### Daily Development Cycle

```bash
# 1. Make changes locally
cd /Users/dgorman/Dev/weatherflow-collector
vim src/collector.py  # or whatever files

# 2. Test locally
docker-compose up -d
docker logs -f wxfdashboardsaio-collector-a1af9766

# 3. Commit to git
git add .
git commit -m "Add feature X"
git push origin main

# 4. Deploy to production
./argo/trigger-deploy.sh

# 5. Monitor deployment
# Either watch the logs:
ssh dgorman@node01.olympusdrive.com 'argo logs -n argo @latest -f'

# Or open Web UI:
open https://argo.olympusdrive.com
```

## Prerequisites (Already Configured)

✅ These should already be set up on your production cluster:

- Argo Workflows installed in `argo` namespace
- GitHub PAT secret: `github-pat-secret` with keys `GIT_USER` and `GIT_PAT`
- PVC for workflow workspace: `argo-workdir-pvc`
- At least one node labeled: `argo-workflows=true`
- Docker registry accessible: `registry.olympusdrive.com`

## Next Steps

### 1. Commit and Push Changes

```bash
cd /Users/dgorman/Dev/weatherflow-collector
git add argo/ DEPLOYMENT.md ARGO_WORKFLOW_SETUP.md
git commit -m "Add Argo Workflow deployment (similar to solardashboard)"
git push origin main
```

### 2. Test First Deployment

```bash
# Trigger the workflow
./argo/trigger-deploy.sh

# Watch it run
ssh dgorman@node01.olympusdrive.com 'argo logs -n argo @latest -f'
```

### 3. Verify Deployment

```bash
# Check pods
ssh dgorman@node01.olympusdrive.com 'kubectl get pods -n weatherflow'

# Check logs
ssh dgorman@node01.olympusdrive.com 'kubectl logs -n weatherflow -l app=weatherflow-collector'

# Verify image tag has git SHA
ssh dgorman@node01.olympusdrive.com 'kubectl get deployment weatherflow-collector -n weatherflow -o yaml | grep image:'
```

## Comparison with SolarDashboard

Both projects now use the same deployment pattern:

### SolarDashboard
- File: `solardashboard/monitoring/argo/solar-dashboard-deploy.yaml`
- Clones: `dgorman/solardashboard` and `dgorman/nightowl`
- Builds: 6 services (multiple Dockerfiles)
- Deploys: Multiple deployments in `solardashboard` namespace

### WeatherFlow Collector
- File: `weatherflow-collector/argo/weatherflow-collector-deploy.yaml`
- Clones: `dgorman/weatherflow-dashboards-aio`
- Builds: 1 service (single Dockerfile)
- Deploys: Collector + InfluxDB in `weatherflow` namespace

### Common Pattern
1. ✅ Git clone from GitHub
2. ✅ Docker-in-Docker build
3. ✅ Git SHA tagging
4. ✅ Registry push
5. ✅ Kubectl apply
6. ✅ Rollout restart
7. ✅ Same node selector: `argo-workflows=true`
8. ✅ Same volumes: `workdir` PVC + `docker-socket` hostPath

## Future Enhancements

### GitHub Webhook Automation

Add automatic deployment on git push:

1. Create EventSource for GitHub webhooks
2. Create Sensor to trigger workflow
3. Configure webhook in GitHub repo settings

Example EventSource:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: EventSource
metadata:
  name: github-weatherflow
  namespace: argo-events
spec:
  github:
    weatherflow:
      repositories:
      - owner: dgorman
        names:
        - weatherflow-dashboards-aio
      webhook:
        endpoint: /weatherflow
        port: "12000"
        method: POST
      events:
      - push
      apiToken:
        name: github-pat-secret
        key: GIT_PAT
```

Example Sensor:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Sensor
metadata:
  name: github-weatherflow
  namespace: argo-events
spec:
  dependencies:
  - name: github-weatherflow
    eventSourceName: github-weatherflow
    eventName: weatherflow
  triggers:
  - template:
      name: weatherflow-workflow
      k8s:
        operation: create
        source:
          resource:
            apiVersion: argoproj.io/v1alpha1
            kind: Workflow
            metadata:
              generateName: weatherflow-collector-deploy-
            spec:
              workflowTemplateRef:
                name: weatherflow-collector-deploy
```

### Notifications

Add Slack notifications on success/failure:

```yaml
# Add to workflow spec
  onExit: exit-handler

# Add template
  - name: exit-handler
    steps:
    - - name: send-notification
        template: slack-notify

  - name: slack-notify
    container:
      image: curlimages/curl
      command: [sh, -c]
      args:
      - |
        curl -X POST $SLACK_WEBHOOK_URL -H 'Content-Type: application/json' \
        -d '{"text":"WeatherFlow deployment {{workflow.status}}"}'
      env:
      - name: SLACK_WEBHOOK_URL
        valueFrom:
          secretKeyRef:
            name: slack-webhook
            key: url
```

### Canary Deployment

Implement progressive rollout:

1. Deploy to canary (10% traffic)
2. Monitor metrics
3. Promote to full deployment if healthy
4. Rollback if errors detected

## Troubleshooting

### Workflow Fails Immediately

Check prerequisites:
```bash
ssh dgorman@node01.olympusdrive.com
kubectl get pvc argo-workdir-pvc -n argo
kubectl get secret github-pat-secret -n argo
kubectl get nodes -l argo-workflows=true
```

### Git Clone Fails

Check GitHub credentials:
```bash
ssh dgorman@node01.olympusdrive.com
kubectl get secret github-pat-secret -n argo -o jsonpath='{.data.GIT_USER}' | base64 -d
# Should output: dgorman
```

### Docker Build Fails

Check workflow logs:
```bash
ssh dgorman@node01.olympusdrive.com 'argo logs -n argo @latest'
```

Common issues:
- Docker daemon not starting (wait longer or increase sleep time)
- Insufficient disk space on node
- Missing Dockerfile in repo

### Deployment Succeeds but Pod CrashLoops

Not a workflow issue - check application logs:
```bash
ssh dgorman@node01.olympusdrive.com 'kubectl logs -n weatherflow -l app=weatherflow-collector'
ssh dgorman@node01.olympusdrive.com 'kubectl describe pod -n weatherflow -l app=weatherflow-collector'
```

## Summary

✅ **What's Ready**:
- Complete Argo Workflow definition
- Helper trigger script
- Documentation
- Deprecation warnings on old scripts

📝 **What You Need to Do**:
1. Commit and push changes to GitHub
2. Sync argo/ directory to production (one-time)
3. Run `./argo/trigger-deploy.sh`
4. Verify deployment

🎯 **Benefits**:
- Git is source of truth (not local dev machine)
- Versioned deployments (git SHA tagging)
- Matches solardashboard pattern
- Automation-ready (webhooks)
- Better visibility (Web UI + logs)
- Reproducible deployments

🚀 **Replaces**:
- Old rsync-based deploy.sh script
- Old setup.sh script
- SSH build commands
- "latest" only tags (now using git SHA)
