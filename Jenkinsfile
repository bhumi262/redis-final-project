
pipeline {
    agent any

    parameters {
        string(
            name: 'APP_ALLOWED_CIDR',
            defaultValue: '103.203.255.50/32',
            description: 'Your public IP/CIDR allowed to access the Flask dashboard'
        )
    }

    stages {
        stage('Clone Repository') {
            steps {
                git branch: 'ha-sentinel',
                    url: 'https://github.com/bhumi262/redis-final-project.git'
            }
        }

        stage('Terraform Init and Validate') {
            steps {
                dir('terraform') {
                    sh '''
                        set -eu
                        terraform init
                        terraform fmt -check
                        terraform validate
                    '''
                }
            }
        }

        stage('Detect Jenkins Public IP') {
            steps {
                sh '''
                    set -eu
                    IP=$(curl -4 -fsS https://checkip.amazonaws.com | tr -d '\\n')
                    echo "$(echo "$IP" | cut -d. -f1-3).0/24" \
                        > "$WORKSPACE/ssh_allowed_cidr.txt"
                    echo "Jenkins SSH CIDR: $(cat "$WORKSPACE/ssh_allowed_cidr.txt")"
                '''
            }
        }

        stage('Terraform Plan') {
            steps {
                dir('terraform') {
                    sh '''
                        set -eu
                        SSH_CIDR=$(cat "$WORKSPACE/ssh_allowed_cidr.txt")

                        terraform plan \
                            -var="ssh_allowed_cidr=$SSH_CIDR" \
                            -var="app_allowed_cidr=$APP_ALLOWED_CIDR" \
                            -out=tfplan
                    '''
                }
            }
        }
        

        stage('Terraform Apply') {
            steps {
                dir('terraform') {
                    sh '''
                        set -eu
                        terraform apply -auto-approve tfplan
                    '''
                }
            }
        }

        stage('Read Infrastructure Outputs') {
            steps {
                dir('terraform') {
                    sh '''
                        set -eu

                        terraform output -raw app_server_public_ip \
                            > "$WORKSPACE/app_ip.txt"

                        terraform output -raw redis_node_1_private_ip \
                            > "$WORKSPACE/redis1_ip.txt"

                        terraform output -raw redis_node_2_private_ip \
                            > "$WORKSPACE/redis2_ip.txt"

                        terraform output -raw redis_node_3_private_ip \
                            > "$WORKSPACE/redis3_ip.txt"

                        echo "App/Bastion public IP:"
                        cat "$WORKSPACE/app_ip.txt"

                        echo "Redis private IPs:"
                        cat "$WORKSPACE/redis1_ip.txt"
                        cat "$WORKSPACE/redis2_ip.txt"
                        cat "$WORKSPACE/redis3_ip.txt"
                    '''
                }
            }
        }

        stage('Wait for App SSH') {
            steps {
                sh '''
                    set -eu
                    APP_IP=$(cat "$WORKSPACE/app_ip.txt")

                    for i in $(seq 1 18); do
                        if nc -z -w5 "$APP_IP" 22; then
                            echo "App/Bastion SSH is reachable."
                            exit 0
                        fi

                        echo "Attempt $i: SSH not ready; retrying in 10 seconds."
                        sleep 10
                    done

                    echo "SSH is not reachable. Check EC2, routes and security groups."
                    exit 1
                '''
            }
        }

        stage('Deploy Redis and Dashboard') {
            steps {
                withCredentials([
                    string(
                        credentialsId: 'redis-project-key',
                        variable: 'PEM_KEY'
                    ),
                    string(
                        credentialsId: 'redis-password',
                        variable: 'REDIS_PASSWORD'
                    )
                ]) {
                    dir('ansible') {
                        sh '''
                            set -eu
                            umask 077

                            APP_IP=$(cat "$WORKSPACE/app_ip.txt")
                            REDIS1=$(cat "$WORKSPACE/redis1_ip.txt")
                            REDIS2=$(cat "$WORKSPACE/redis2_ip.txt")
                            REDIS3=$(cat "$WORKSPACE/redis3_ip.txt")

                            KEY_FILE=$(mktemp)
                            VARS_FILE=$(mktemp)
                            trap 'rm -f "$KEY_FILE" "$VARS_FILE"' EXIT

                            printf '%s' "$PEM_KEY" \
                                | tr -d ' \\r\\n' \
                                | base64 -d > "$KEY_FILE"
                            chmod 600 "$KEY_FILE"

                            # Create Ansible extra-vars JSON without
                            # writing the Redis password into Git.
                            printf '%s' "$REDIS_PASSWORD" |
                                python3 -c \
                                'import json,sys; print(json.dumps({"redis_password":sys.stdin.read()}))' \
                                > "$VARS_FILE"
                            chmod 600 "$VARS_FILE"

                            cat > inventory.ini <<EOF
[app_server]
app ansible_host=$APP_IP ansible_user=ubuntu ansible_python_interpreter=/usr/bin/python3 ansible_ssh_private_key_file=$KEY_FILE ansible_ssh_common_args='-o StrictHostKeyChecking=no'

[redis_nodes]
redis1 ansible_host=$REDIS1 ansible_user=ubuntu ansible_python_interpreter=/usr/bin/python3 ansible_ssh_private_key_file=$KEY_FILE ansible_ssh_common_args='-o ProxyCommand="ssh -i $KEY_FILE -o StrictHostKeyChecking=no -W %h:%p ubuntu@$APP_IP" -o StrictHostKeyChecking=no' redis_node_role=primary redis_primary_host=$REDIS1
redis2 ansible_host=$REDIS2 ansible_user=ubuntu ansible_python_interpreter=/usr/bin/python3 ansible_ssh_private_key_file=$KEY_FILE ansible_ssh_common_args='-o ProxyCommand="ssh -i $KEY_FILE -o StrictHostKeyChecking=no -W %h:%p ubuntu@$APP_IP" -o StrictHostKeyChecking=no' redis_node_role=replica redis_primary_host=$REDIS1
redis3 ansible_host=$REDIS3 ansible_user=ubuntu ansible_python_interpreter=/usr/bin/python3 ansible_ssh_private_key_file=$KEY_FILE ansible_ssh_common_args='-o ProxyCommand="ssh -i $KEY_FILE -o StrictHostKeyChecking=no -W %h:%p ubuntu@$APP_IP" -o StrictHostKeyChecking=no' redis_node_role=replica redis_primary_host=$REDIS1

[redis_nodes:vars]
ansible_python_interpreter=/usr/bin/python3
EOF

                            ansible-playbook \
                                -i inventory.ini \
                                playbook.yml \
                                --extra-vars "@$VARS_FILE"
                        '''
                    }
                }
            }
        }

        stage('Deployment Summary') {
            steps {
                sh '''
                    echo "=================================="
                    echo "Redis HA deployment stages completed"
                    echo "App/Bastion IP: $(cat "$WORKSPACE/app_ip.txt")"
                    echo "Dashboard URL: http://$(cat "$WORKSPACE/app_ip.txt"):5000"
                    echo "Redis nodes: private network only"
                    echo "=================================="
                '''
            }
        }
    }

    post {
        success {
            echo 'SUCCESS: Pipeline stages completed.'
        }

        failure {
            echo 'FAILED: Inspect the failed stage logs before retrying.'
        }
    }
}