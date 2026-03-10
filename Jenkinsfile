pipeline {
  agent any

  environment {
    // ---- SonarQube settings ----
    // New project key since this is a new repo/app in SonarQube
    SONAR_PROJECT_KEY = "hello-service"

    // Name of SonarQube server config in Jenkins:
    // Manage Jenkins -> System -> SonarQube servers -> Name
    SONARQUBE_SERVER_NAME = "sonarqube"

    // ---- Deploy settings ----
    APP_NAME     = "hello-service"
    APP_HOME     = "/opt/apps/hello-service"
    SERVICE_NAME = "hello-service"
  }

  options {
    // Adds timestamps to Jenkins console logs
    timestamps()

    // Prevents overlapping deployments from concurrent builds
    disableConcurrentBuilds()
  }

  triggers {
    // Optional: poll SCM every 2 minutes (matches your existing pattern)
    // You can remove this if you're using GitHub webhooks instead
    pollSCM('H/2 * * * *')
  }

  stages {

    stage('Checkout') {
      // Pull source code from Git (based on job SCM config)
      steps {
        checkout scm
      }
    }

    stage('Build & Unit Test') {
      // Compile + run unit tests; produces surefire JUnit XML reports
      steps {
        sh 'mvn -B -U clean test'
      }
      post {
        always {
          // Publish test reports into Jenkins UI (test trend, failures)
          junit testResults: '**/target/surefire-reports/*.xml', allowEmptyResults: false
        }
      }
    }

    stage('SonarQube Scan') {
      // Run static analysis and publish results to SonarQube
      steps {
        script {
          // Primary path: use Jenkins SonarQube plugin config (recommended)
          try {
            withSonarQubeEnv("${SONARQUBE_SERVER_NAME}") {
              sh """
                mvn -B sonar:sonar \
                  -Dsonar.projectKey=${SONAR_PROJECT_KEY}
              """
            }
          } catch (Exception e) {
            // Fallback path (only if withSonarQubeEnv isn't available)
            // Keep only if you're unsure about plugin availability.
            echo "withSonarQubeEnv not available; falling back to explicit sonar.host.url"
            sh """
              mvn -B sonar:sonar \
                -Dsonar.projectKey=${SONAR_PROJECT_KEY} \
                -Dsonar.host.url=http://localhost:9000
            """
          }
        }
      }
    }

    stage('Quality Gate') {
      // Wait for SonarQube to compute the Quality Gate and notify Jenkins via webhook.
      // If webhook is misconfigured, this stage typically waits until timeout.
      steps {
        timeout(time: 5, unit: 'MINUTES') {
          waitForQualityGate abortPipeline: true
        }
      }
    }

    stage('Package') {
      // Build the runnable jar (skips tests because they already ran)
      steps {
        sh 'mvn -B -DskipTests package'
        sh 'ls -lah target/*.jar'
      }
      post {
        success {
          // Archive jar as a Jenkins build artifact (traceability + download)
          archiveArtifacts artifacts: 'target/*.jar', fingerprint: true
        }
      }
    }

    stage('Deploy + Healthcheck (main only)') {
      // Only deploy from main branch to avoid random feature branches deploying
      when { branch 'main' }

      steps {
        sh 'chmod +x ci/deploy/*.sh'

        script {
          // Pick the jar produced in target/
          def jarPath = sh(script: "ls -1 target/*.jar | head -n 1", returnStdout: true).trim()

          // Release ID used to create a versioned folder under /opt/apps/hello-service/releases/<releaseId>
          def shortSha = sh(script: "git rev-parse --short HEAD", returnStdout: true).trim()
          def releaseId = "${env.BUILD_NUMBER}_${shortSha}"

          // Try deploy; if deploy/healthcheck fails, rollback automatically
          try {
            sh "./ci/deploy/deploy.sh ${APP_NAME} ${jarPath} ${releaseId} ${APP_HOME} ${SERVICE_NAME}"
            sh "./ci/deploy/healthcheck.sh ${APP_NAME} ${APP_HOME}"
          } catch (err) {
            echo "Deploy or healthcheck failed. Attempting rollback..."
            sh "./ci/deploy/rollback.sh ${APP_NAME} ${APP_HOME} ${SERVICE_NAME} || true"
            // Re-throw so build still fails (don’t hide failures)
            throw err
          }
        }
      }
    }
  }

  post {
    always {
      // Helpful runtime status for debugging in Jenkins logs
      sh "sudo systemctl status ${SERVICE_NAME} --no-pager || true"
      sh "journalctl -u ${SERVICE_NAME} -n 80 --no-pager || true"
    }
  }
}