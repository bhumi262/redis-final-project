
pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        timeout(time: 60, unit: 'MINUTES')
    }

    parameters {
        string(
            name: 'APP_ALLOWED_CIDR',
            defaultValue: '103.203.255.50/32',
            description: 'Your laptop public IP with /32, allowed to access the Flask dashboard'
        )
    }

    environment {
        AWS_DEFAULT_REGION = 'ap-south-1'
        TF_DIR = 'terraform'
        INVENTORY_FILE = 'ansible/inventory.ini'
        ANSIBLE_HOST_KEY_CHECKING = 'False'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm

                sh '''
                    set -eu
                    echo "Repository checked out."
                    echo "Branch: $(git branch --show-current)"
                    echo "Commit: $(git rev-parse --short HEAD)"
                '''
            }
        }

        stage('Detect Jenkins Public IP') {
            steps {
                sh '''
                    set -eu

                    command -v curl >/dev/null 2>&1 || {
                        echo "ERROR: curl is required on the Jenkins agent."
                        exit 1
                    }

                    IP=$(curl -4 -fsS --max-time 15 \
                        https://checkip.amazonaws.com | tr -d '[:space:]')

                    echo "$IP" | grep -Eq \
                        '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' || {
                        echo "ERROR: Could not detect Jenkins public IPv4."
                        exit 1
                    }

                    echo "$IP/32" > "$WORKSPACE/ssh_allowed_cidr.txt"

                    echo "Jenkins SSH access CIDR detected."
                    echo "The dashboard CIDR is configured separately."
                '''
            }
        }

        stage('Terraform Init and Validate') {
            steps {
                dir('terraform') {
                    sh '''
                        set -eu
                        terraform init -input=false
                        terraform fmt -check -recursive
                        terraform validate
                    '''
                }
            }
        }

        stage('Terraform Plan') {
            steps {
                withCredentials([
                    string(
                        credentialsId: 'redis-password',
                        variable: 'REDIS_PASSWORD'
                    )
                ]) {
                    sh '''
                        set -eu

                        SSH_CIDR=$(cat "$WORKSPACE/ssh_allowed_cidr.txt")

                        # Validate dashboard CIDR format.
                        python3 - "$APP_ALLOWED_CIDR" <<'PY'
import ipaddress
import sys

try:
    ipaddress.ip_network(sys.argv[1], strict=False)
except ValueError:
    print("ERROR: APP_ALLOWED_CIDR must be a valid IP/CIDR, e.g. 1.2.3.4/32")
    sys.exit(1)
PY

                        # Keep the password out of the Terraform command line.
                        export TF_VAR_redis_password="$REDIS_PASSWORD"

                        terraform -chdir="$TF_DIR" plan \
                            -input=false \
                            -var="ssh_allowed_cidr=$SSH_CIDR" \
                            -var="app_allowed_cidr=$APP_ALLOWED_CIDR" \
                            -out=tfplan
                    '''
                }
            }
        }

        stage('Terraform Apply') {
            steps {
                input(
                    message: 'Review the Terraform plan and approve creation of AWS resources?',
                    ok: 'Approve and Create'
                )

                sh '''
                    set -eu
                    terraform -chdir="$TF_DIR" apply \
                        -input=false \
                        -auto-approve tfplan
                '''
            }
        }

        stage('Read Infrastructure Outputs') {
            steps {
                script {
                    env.APP_PUBLIC_IP = sh(
                        script: 'terraform -chdir="$TF_DIR" output -raw app_server_public_ip',
                        returnStdout: true
                    ).trim()

                    env.REDIS1_IP = sh(
                        script: 'terraform -chdir="$TF_DIR" output -raw redis_node_1_private_ip',
                        returnStdout: true
                    ).trim()

                    env.REDIS2_IP = sh(
                        script: 'terraform -chdir="$TF_DIR" output -raw redis_node_2_private_ip',
                        returnStdout: true
                    ).trim()

                    env.REDIS3_IP = sh(
                        script: 'terraform -chdir="$TF_DIR" output -raw redis_node_3_private_ip',
                        returnStdout: true
                    ).trim()
                }

                sh '''
                    set -eu
                    echo "Infrastructure outputs retrieved."
                    echo "App server public IP: $APP_PUBLIC_IP"
                    echo "Redis node 1 private IP: $REDIS1_IP"
                    echo "Redis node 2 private IP: $REDIS2_IP"
                    echo "Redis node 3 private IP: $REDIS3_IP"
                '''
            }
        }

        stage('Prepare SSH Key and Ansible Inventory') {
            steps {
                withCredentials([
                    string(
                        credentialsId: 'redis-project-key',
                        variable: 'SSH_KEY_B64'
                    )
                ]) {
                    sh '''
                        set -eu
                        umask 077

                        KEY_FILE="$WORKSPACE/redis-project-key.pem"

                        # Jenkins credential must contain the Base64-encoded PEM key.
                        printf '%s' "$SSH_KEY_B64" | base64 -d > "$KEY_FILE"
                        chmod 600 "$KEY_FILE"

                        cat > "$WORKSPACE/$INVENTORY_FILE" <<EOF
[app_server]
app ansible_host=${APP_PUBLIC_IP} ansible_user=ubuntu ansible_ssh_private_key_file=${KEY_FILE} ansible_python_interpreter=/usr/bin/python3

[redis_nodes]
redis1 ansible_host=${REDIS1_IP} ansible_user=ubuntu ansible_ssh_private_key_file=${KEY_FILE} ansible_python_interpreter=/usr/bin/python3 redis_node_role=primary redis_primary_host=${REDIS1_IP}
redis2 ansible_host=${REDIS2_IP} ansible_user=ubuntu ansible_ssh_private_key_file=${KEY_FILE} ansible_python_interpreter=/usr/bin/python3 redis_node_role=replica redis_primary_host=${REDIS1_IP}
redis3 ansible_host=${REDIS3_IP} ansible_user=ubuntu ansible_ssh_private_key_file=${KEY_FILE} ansible_python_interpreter=/usr/bin/python3 redis_node_role=replica redis_primary_host=${REDIS1_IP}

[redis_nodes:vars]
ansible_ssh_common_args='-o ProxyCommand="ssh -i ${KEY_FILE} -o StrictHostKeyChecking=no -W %h:%p ubuntu@${APP_PUBLIC_IP}"'

[app_server:vars]
ansible_python_interpreter=/usr/bin/python3
EOF

                        echo "Ansible inventory generated."
                    '''
                }
            }
        }

        stage('Wait for SSH Access') {
            steps {
                withCredentials([
                    string(
                        credentialsId: 'redis-project-key',
                        variable: 'SSH_KEY_B64'
                    )
                ]) {
                    sh '''
                        set -eu
                        umask 077

                        KEY_FILE="$WORKSPACE/redis-project-key.pem"
                        printf '%s' "$SSH_KEY_B64" | base64 -d > "$KEY_FILE"
                        chmod 600 "$KEY_FILE"

                        echo "Waiting for the app EC2 SSH service..."

                        ATTEMPT=1
                        until ssh \
                            -i "$KEY_FILE" \
                            -o BatchMode=yes \
                            -o ConnectTimeout=8 \
                            -o StrictHostKeyChecking=no \
                            "ubuntu@$APP_PUBLIC_IP" true
                        do
                            if [ "$ATTEMPT" -ge 30 ]; then
                                echo "ERROR: App EC2 SSH is not reachable."
                                exit 1
                            fi

                            ATTEMPT=$((ATTEMPT + 1))
                            sleep 10
                        done

                        echo "App EC2 SSH is ready."
                    '''
                }
            }
        }

        stage('Configure Redis HA and Deploy Dashboard') {
            steps {
                withCredentials([
                    string(
                        credentialsId: 'redis-password',
                        variable: 'REDIS_PASSWORD'
                    ),
                    string(
                        credentialsId: 'redis-project-key',
                        variable: 'SSH_KEY_B64'
                    )
                ]) {
                    sh '''
                        set -eu
                        umask 077

                        KEY_FILE="$WORKSPACE/redis-project-key.pem"
                        VARS_FILE="$WORKSPACE/redis-secret-vars.json"

                        printf '%s' "$SSH_KEY_B64" | base64 -d > "$KEY_FILE"
                        chmod 600 "$KEY_FILE"

                        # Write secrets as JSON rather than exposing them in command arguments.
                        python3 -c \
                            'import json,os; print(json.dumps({"redis_password": os.environ["REDIS_PASSWORD"]}))' \
                            > "$VARS_FILE"
                        chmod 600 "$VARS_FILE"

                        # Update the inventory with the key path used by this build.
                        sed -i "s|ansible_ssh_private_key_file=.*ansible_python_interpreter|ansible_ssh_private_key_file=$KEY_FILE ansible_python_interpreter|g" \
                            "$WORKSPACE/$INVENTORY_FILE"

                        # Ansible needs the Docker collection on the Jenkins agent.
                        ansible-galaxy collection install community.docker

                        ansible-playbook \
                            -i "$WORKSPACE/$INVENTORY_FILE" \
                            "$WORKSPACE/ansible/playbook.yml" \
                            --extra-vars "@$VARS_FILE"
                    '''
                }
            }
        }

        stage('Deployment Summary') {
            steps {
                echo 'Redis HA and Flask deployment stages completed.'

                echo "Dashboard URL: http://${APP_PUBLIC_IP}:5000"
                echo "Redis node 1 private IP: ${REDIS1_IP}"
                echo "Redis node 2 private IP: ${REDIS2_IP}"
                echo "Redis node 3 private IP: ${REDIS3_IP}"

                echo 'Open the dashboard URL only if your current public IP is allowed by the app security group.'
            }
        }
    }

    post {
        success {
            echo 'Pipeline completed successfully.'
        }

        failure {
            echo 'Pipeline failed. Check the first failed stage in the Jenkins console log.'
        }

        always {
            sh '''
                rm -f "$WORKSPACE/redis-project-key.pem"
                rm -f "$WORKSPACE/redis-secret-vars.json"
                rm -f "$WORKSPACE/ssh_allowed_cidr.txt"
            '''
        }
    }
}
