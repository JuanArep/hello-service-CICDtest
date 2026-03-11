# hello-service CI/CD (WSL Ubuntu 22.04 + Jenkins + SonarQube + systemd)

This repo is a minimal Java service used to learn and validate an enterprise-style CI/CD flow on a single host (WSL Ubuntu 22.04). It includes:
- A Maven-built Java app producing a runnable JAR
- Unit tests with JUnit reporting
- SonarQube analysis + Quality Gate enforcement
- Deployment on the same WSL host using **symlink-based releases** + **systemd**
- Healthcheck and rollback automation via scripts

> Evidence level: this README reflects the concrete setup we implemented in WSL + Jenkins in this project (not generic guidance).

---

## 1) What we built (end-to-end flow)

### CI (every build)
1. Checkout source from GitHub
2. `mvn clean test`  
   - runs unit tests
   - generates Surefire reports (JUnit XML)
   - Jenkins publishes test results
3. SonarQube scan (`mvn sonar:sonar`)
4. SonarQube Quality Gate (`waitForQualityGate`)
5. `mvn -DskipTests package`
6. Archive build artifact (`target/*.jar`)

### CD (deployment on the same WSL host)
7. Copy JAR into a new release directory: `/opt/apps/hello-service/releases/<releaseId>/app.jar`
8. Copy config into release: `/opt/apps/hello-service/releases/<releaseId>/app.env`
9. Switch `/opt/apps/hello-service/current` symlink to the new release
10. Restart systemd service: `hello-service`
11. Healthcheck `/actuator/health`
12. If healthcheck fails: rollback to previous release (symlink revert + restart)

---

## 2) Repo contents

### Source code (app)
- `src/main/java/...`
  - `DemoApplication.java` – app entrypoint
  - `HelloController.java` – sample endpoint
- `src/main/resources/application.properties`
  - uses `SERVER_PORT` env var with default `8081`
  - exposes Actuator endpoints for health
- `src/test/java/...`
  - `HelloControllerTest.java` – unit test example

### Build config
- `pom.xml`
  - Java 17
  - Spring Boot dependencies
  - Actuator for `/actuator/health`
  - **maven-surefire-plugin pinned to 3.x** to support JUnit 5 (required; older Surefire ran 0 tests)

### CI/CD scripts
- `ci/deploy/deploy.sh`
  - creates release dir
  - copies jar + env
  - updates symlink
  - restarts systemd service
- `ci/deploy/healthcheck.sh`
  - sources `current/app.env`
  - polls `HEALTH_URL` until OK or timeout
- `ci/deploy/rollback.sh`
  - repoints symlink to previous release
  - restarts service
- `ci/config/app.env.example`
  - example runtime config (port, JVM opts, health URL)

### Pipeline
- `Jenkinsfile`
  - CI stages: Build/Test → Sonar Scan → Quality Gate → Package → Archive
  - CD stage: Deploy + Healthcheck (now enabled for this lab)
  - Post actions: status/log output for debugging (hardened with `sudo -n` recommended)

---

## 3) WSL host folder structure (deployment layout)

- We deployed to a conventional Linux location for third-party apps:
 - /opt/apps/hello-service/
 - releases/
 - bootstrap/
 - app.env
 - <releaseId>/
 - app.jar
 - app.env
 - current -> /opt/apps/hello-service/releases/<releaseId>
 - run/ (optional; systemd manages PID, but kept for future runtime files)
 - logs/ (optional; we use journald currently)

 
### Purpose of each folder
- `releases/`
  - immutable versioned deployments for rollback
- `releases/bootstrap/app.env`
  - “known good” baseline env file to copy from for new releases
- `current` (symlink)
  - points to the active release directory
  - deployment becomes an atomic pointer switch
- `run/`
  - reserved for runtime state (PID files etc.); not required when using systemd
- `logs/`
  - reserved for file logs if needed; current setup logs to journald

### Why symlink-based release deployment
- fast rollback (repoint symlink)
- avoids overwriting in-place
- keeps deployment atomic and auditable

---

## 4) systemd service (process manager)

The app runs as a systemd service named:
- `hello-service.service`

It always starts whatever is under:
- `/opt/apps/hello-service/current/app.jar`

and reads runtime config from:
- `/opt/apps/hello-service/current/app.env`

### Typical systemd commands
```bash
sudo systemctl status hello-service --no-pager
sudo systemctl restart hello-service
sudo journalctl -u hello-service -n 120 --no-pager
```

### 5) Runtime config: app.env

Location:
- Active config: /opt/apps/hello-service/current/app.env
- Per-release config: /opt/apps/hello-service/releases/<releaseId>/app.env

Example content:
```bash
APP_PORT=8081
JAVA_OPTS="-Xms256m -Xmx512m"
APP_ARGS=""
HEALTH_URL="http://localhost:8081/actuator/health"
```

### 6) Jenkins Setup notes (local Jenkins on WSL)

Job type
- Pipeline from SCM
- Points to this GitHub repo
- Script path: Jenkinsfile

Credentials
- GitHub PAT credential for checkout (already configured)

SonarQube
- SonarQube is installed locally (commonly via Docker)
- Jenkins uses withSonarQubeEnv('sonarqube')
- SonarQube Quality Gate uses webhook callback to Jenkins:
    - webhook endpoint: /sonarqube-webhook/
    - from container-to-host example: http://172.17.0.1:8080/sonarqube-webhook/
    - curl -i http://localhost:8080/sonarqube-webhook/ returning 405 is expected (endpoint exists; GET not allowed)

Permissions (required for deployment automation)
- Jenkins needs controlled elevated rights to:
    - restart/status the service via systemctl
    - write to /opt/apps/hello-service during deploy
- We used sudoers rules to allow non-interactive sudo for the exact commands used (including args like --no-pager).

### 7) How to run locally (developer sanity check)

- Build + test
```bash
mvn -B clean test
```

- Package
```bash
mvn -B -DskipTests package
```
- Run locally without systemd (for quick dev test)
```bash
java -jar target/hello-service-1.0.0.jar
Check endpoints
curl -fsS http://localhost:8081/hello
curl -fsS http://localhost:8081/actuator/health
```

### 8) Manual deploy (outside Jenkins)

- If you built the jar locally:
```bash
REL_ID="$(date +%Y%m%d_%H%M%S)_$(git rev-parse --short HEAD)"
./ci/deploy/deploy.sh hello-service "target/"*.jar "$REL_ID"
./ci/deploy/healthcheck.sh hello-service /opt/apps/hello-service
```

- Rollback:
```bash
./ci/deploy/rollback.sh hello-service /opt/apps/hello-service hello-service
./ci/deploy/healthcheck.sh hello-service /opt/apps/hello-service
```