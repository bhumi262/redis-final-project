
pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        timeout(time: 60, unit: 'MINUTES')
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
                    echo "Branch: $(git branch --show-current)"
                    echo "Commit: $(git rev-parse --short HEAD)"
                '''
            }
        }

        stage('Detect Public IP') {
            steps {
                sh '''
                    set -eu

                    IP=$(curl -4 -fsS --max-time 15 \
                        https://checkip.amazonaws.com | tr -d '[:space:]')

                    python3 - "$IP" <<'PY'
import ipaddress
import sys
try:
    ipaddress.IPv4Address(sys.argv[1])
except ValueError:
    print("ERROR: Invalid public IPv4 address")
    sys.exit(1)
PY

                    echo "$IP/32" > "$WORKSPACE/ssh_allowed_cidr.txt"
                    echo "$IP/32" > "$WORKSPACE/app_allowed_cidr.txt"

                    echo "Public IP detected automatically."
                    echo "SSH and dashboard access CIDRs generated."
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

                        export TF_VAR_redis_password="$REDIS_PASSWORD"

                        SSH_CIDR=$(cat "$WORKSPACE/ssh_allowed_cidr.txt")
                        APP_CIDR=$(cat "$WORKSPACE/app_allowed_cidr.txt")

                        terraform -chdir="$TF_DIR" plan \
                            -input=false \
                            -var="ssh_allowed_cidr=$SSH_CIDR" \
                            -var="app_allowed_cidr=$APP_CIDR" \
                            -out=tfplan
                    '''
                }
            }
        }

        stage('Approve and Apply Infrastructure') {
            steps {
                input(
                    message: 'Review the Terraform plan before creating AWS resources.',
                    ok: 'Approve'
                )

                sh '''
                    set -eu
                    terraform -chdir="$TF_DIR" apply \
                        -input=false \
                        -auto-approve tfplan
                '''
            }
        }

        stage('Read Terraform Outputs') {
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
                    echo "App public IP: $APP_PUBLIC_IP"
                    echo "Redis 1 private IP: $REDIS1_IP"
                    echo "Redis 2 private IP: $REDIS2_IP"
                    echo "Redis 3 private IP: $REDIS3_IP"
                '''
            }
        }

        stage('Prepare SSH Key and Inventory') {
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

        stage('Wait for App SSH') {
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

                        ATTEMPT=1
                        until ssh -i "$KEY_FILE" \
                            -o BatchMode=yes \
                            -o ConnectTimeout=8 \
                            -o StrictHostKeyChecking=no \
                            "ubuntu@$APP_PUBLIC_IP" true
                        do
                            if [ "$ATTEMPT" -ge 30 ]; then
                                echo "ERROR: App SSH is not reachable."
                                exit 1
                            fi

                            ATTEMPT=$((ATTEMPT + 1))
                            sleep 10
                        done

                        echo "App SSH is ready."
                    '''
                }
            }
        }

        stage('Deploy Redis Sentinel and Dashboard') {
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

                        python3 -c \
                          'import json,os; print(json.dumps({"redis_password":os.environ["REDIS_PASSWORD"]}))' \
                          > "$VARS_FILE"
                        chmod 600 "$VARS_FILE"

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
                echo "Dashboard URL: http://${APP_PUBLIC_IP}:5000"
                echo "Redis Sentinel HA deployment stages completed."
            }
        }
    }

    post {
        success {
            echo 'Pipeline completed successfully.'
        }

        failure {
            echo 'Pipeline failed. Check the first failed stage in Console Output.'
        }

        always {
            sh '''
                rm -f "$WORKSPACE/redis-project-key.pem"
                rm -f "$WORKSPACE/redis-secret-vars.json"
                rm -f "$WORKSPACE/ssh_allowed_cidr.txt"
                rm -f "$WORKSPACE/app_allowed_cidr.txt"
            '''
        }
    }
}
