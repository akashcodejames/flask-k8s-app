# Self-Hosted Runner Setup Guide for Mac M2

This guide will help you connect your local Mac to GitHub Actions so it can automatically deploy updates to your local Kind cluster.

## 1. Add Runner to GitHub

1. Go to your repository on GitHub: https://github.com/akashcodejames/flask-k8s-app
2. Click **Settings** (top tab) -> **Actions** (left sidebar) -> **Runners**.
3. Click the green **New self-hosted runner** button.
4. Select **macOS** as the runner image.
5. Select **ARM64** as the architecture (since you are on M2).

## 2. Install Runner on Your Mac

Run the following commands in your terminal (one by one, as provided by GitHub):

> **Note:** Do not run these inside the project folder. Create a separate folder for the runner.

```bash
# Create a folder for the runner
mkdir actions-runner && cd actions-runner

# Download the latest runner package (Check GitHub for the exact version URL provided)
curl -o actions-runner-osx-arm64.tar.gz -L https://github.com/actions/runner/releases/download/v2.321.0/actions-runner-osx-arm64-2.321.0.tar.gz

# Extract the installer
tar xzf ./actions-runner-osx-arm64.tar.gz

# Configure the runner (Replace TOKEN with the one from GitHub page)
./config.sh --url https://github.com/akashcodejames/flask-k8s-app --token <YOUR_TOKEN_HERE>
```

- When asked for the name of the runner group, press **Enter** (default).
- When asked for the name of runner, press **Enter** (default).
- When asked for work folder, press **Enter**.

## 3. Run the Runner

To start listening for jobs:

```bash
./run.sh
```

Keep this terminal window open! It needs to be running to accept deployment jobs.

> **Tip:** To run it in the background as a service, exit with `Ctrl+C` and use:
> `./svc.sh install` then `./svc.sh start`

## 4. That's it!

Now, whenever you push code to `main`:
1. GitHub will build the Docker images (for ARM64/M2).
2. The `deploy-to-local` job will trigger on YOUR Mac.
3. It will download the new images, load them into Kind, and update your cluster automatically via `kubectl`.
