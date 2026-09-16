# Macky Merch API - DevSecOps Starter

Baseline Express.js API for the LSCS DevSecOps Engineering Exam, containerized with Docker and wrapped in a security-focused GitHub Actions CI/CD pipeline.

## Setup Instructions

### Prerequisites
- [Node.js 20+](https://nodejs.org/)
- [Docker Desktop](https://www.docker.com/products/docker-desktop/)

### Run locally (without Docker)
```bash
npm install
npm start
```
The server runs on `http://localhost:3000`. Check the health endpoint at `http://localhost:3000/health`.

### Run tests
```bash
npm test
```

### Build and run with Docker
```bash
docker build -t devsecops-exam-starter .
docker run -p 3000:3000 devsecops-exam-starter
```
Then verify: `curl http://localhost:3000/health`

### CI/CD
Every push and pull request to `main` automatically triggers `.github/workflows/ci.yml`, which builds, tests, and security-scans the project. See [CI/CD Pipeline](#cicd-pipeline) below.

## Architecture

### Why `node:20-alpine` as the base image
The `Dockerfile` uses a **multi-stage build** on `node:20-alpine`:
- **Alpine Linux** is a minimal distribution (~5MB base), which keeps the final image small, reduces the attack surface (fewer installed packages/binaries means fewer potential CVEs), and speeds up builds/pulls.
- **Node 20** is the current active LTS release at the time of writing, so it receives security patches and matches the Node version used in CI (`actions/setup-node@v4` with `node-version: '20'`), keeping local, CI, and container environments consistent.
- The **multi-stage build** separates dependency installation (`npm ci --omit=dev`) from the final runtime image, so devDependencies, build caches, and source files not needed at runtime never end up in the shipped image.
- The container **runs as the non-root `node` user** (built into the official Node image) instead of root, following the principle of least privilege — if the container is ever compromised, the attacker doesn't gain root inside it.

### Security scanners used and why
The CI pipeline layers multiple, complementary types of scanning rather than relying on one tool:

| Scanner | Type | Why chosen |
|---|---|---|
| **`npm audit`** | Dependency scanning | Built into npm, requires no extra setup/API keys, and checks `package-lock.json` directly against the npm/GitHub advisory database. It's the fastest way to catch known-vulnerable JS packages (like the `lodash` version below) with zero added tooling cost. |
| **Trivy** (`aquasecurity/trivy-action`) | Container image scanning | Scans the *built Docker image* itself, not just `package.json` — this catches vulnerabilities in OS packages (Alpine) and transitive dependencies baked into the final artifact, which `npm audit` alone can't see. It's open-source, fast, and widely adopted for image scanning in CI. |
| **TruffleHog** | Secret scanning | Scans the full git history (not just the working tree) for accidentally committed credentials such as API keys, tokens, and passwords, using verification against live services to reduce false positives (`--only-verified`). |
| **CodeQL** | Static Application Security Testing (SAST) | GitHub-native, requires no external account/API key, and analyzes actual code paths (e.g. injection, unsafe deserialization) rather than just dependency metadata. Results are uploaded directly to the repo's Security tab. |

Together these cover the three main risk categories: vulnerable dependencies, leaked secrets, and insecure code patterns.

### CI/CD Pipeline
`.github/workflows/ci.yml` runs on every push/PR to `main` with four jobs:
1. **`build-and-test`** — checks out code, sets up Node 20, runs `npm install`, `npm test`, and builds the Docker image to validate the `Dockerfile`.
2. **`dependency-scan`** — runs `npm audit` and scans the built Docker image with Trivy; fails the build on moderate+ (npm) or CRITICAL/HIGH (Trivy) findings.
3. **`secret-scan`** — runs TruffleHog against the full repo history.
4. **`codeql-analysis`** — runs GitHub CodeQL static analysis for JavaScript.

## Vulnerability Demonstration

To prove the dependency-scanning gate works, `package.json` deliberately pins an outdated, vulnerable version of `lodash`:

```json
"dependencies": {
  "express": "^4.18.2",
  "lodash": "^4.17.15"
}
```

`lodash@4.17.15` is affected by known CVEs, including:
- **CVE-2020-8203** — Prototype Pollution in `lodash` before 4.17.19
- **CVE-2021-23337** — Command Injection via the `template` function, fixed in 4.17.21

### Reproducing the finding locally
```bash
npm install
npm audit
```
Expected output includes a **moderate/high severity** advisory for `lodash`, recommending an upgrade to `>=4.17.21`.

### Reproducing the finding in CI
Push a commit (or open a PR) to `main`. The **`dependency-scan`** job's `npm audit` step will fail with output similar to:

```
# npm audit report

lodash  <=4.17.20
Severity: high
Prototype Pollution in lodash - https://github.com/advisories/GHSA-p6mc-m468-83gw
Command Injection in lodash - https://github.com/advisories/GHSA-35jh-r3h4-6jhm
fix available via `npm audit fix`
node_modules/lodash

1 vulnerability (1 high)
```

This confirms the pipeline correctly detects and blocks a build containing a known-vulnerable dependency, satisfying the exam's vulnerability-demonstration requirement.

### Remediation
Upgrading resolves the finding:
```bash
npm install lodash@latest
```
After upgrading, `npm audit` and the CI `dependency-scan` job should pass cleanly.
