pipeline {
    agent any

    stages {
        stage('Clone Repository') {
            steps {
                git branch: 'main',
                    url: 'https://github.com/bhumi262/redis-final-project.git'
            }
        }

        stage('Terraform Init') {
            steps {
                dir('terraform') {
                    sh 'terraform init'
                }
            }
        }

        stage('Detect Jenkins Public IP') {
            steps {
                sh '''
                    set -eu
                    IP=$(curl -4 -fsS https://checkip.amazonaws.com | tr -d '\\n')
                    echo "$(echo "$IP" | cut -d. -f1-3).0/24" > "$WORKSPACE/ssh_allowed_cidr.txt"
                    echo "Jenkins SSH allowlist: $(cat "$WORKSPACE/ssh_allowed_cidr.txt")"
                '''
            }
        }

        stage('Terraform Plan') {
            steps {
                dir('terraform') {
                    sh '''
                        set -eu
                        SSH_CIDR=$(cat "$WORKSPACE/ssh_allowed_cidr.txt")
                        terraform plan -var="ssh_allowed_cidr=$SSH_CIDR" -var="app_allowed_cidr=$SSH_CIDR"
                    '''
                }
            }
        }

        stage('Terraform Apply') {
            steps {
                dir('terraform') {
                    sh '''
                        set -eu
                        SSH_CIDR=$(cat "$WORKSPACE/ssh_allowed_cidr.txt")
                        terraform apply -auto-approve -var="ssh_allowed_cidr=$SSH_CIDR" -var="app_allowed_cidr=$SSH_CIDR"
                    '''
                }
            }
        }

        stage('Save EC2 IP') {
            steps {
                dir('terraform') {
                    sh '''
                        set -eu
                        terraform output -raw redis_server_public_ip > "$WORKSPACE/redis_ip.txt"
                        echo "EC2 Public IP saved successfully."
                    '''
                }
            }
        }

        stage('Wait for SSH') {
            steps {
                sh '''
                    set -eu
                    IP=$(cat "$WORKSPACE/redis_ip.txt")
                    echo "Waiting for SSH on $IP..."

                    for i in $(seq 1 15); do
                        if nc -vz -w5 "$IP" 22; then
                            echo "SSH is ready!"
                            exit 0
                        fi

                        echo "Attempt $i: SSH not ready. Retrying in 10 seconds..."
                        sleep 10
                    done

                    echo "SSH did not become ready. Check EC2 security group and network."
                    exit 1
                '''
            }
        }

        stage('Prepare Ansible Inventory') {
            steps {
                dir('ansible') {
                    sh '''
                        set -eu
                        IP=$(cat "$WORKSPACE/redis_ip.txt")

                        cat > inventory.ini <<EOF
[redis_server]
$IP ansible_user=ubuntu ansible_ssh_private_key_file=/var/lib/jenkins/redis-project/redis-project-key.pem ansible_ssh_common_args='-o StrictHostKeyChecking=no'
EOF

                        echo "Ansible inventory prepared."
                    '''
                }
            }
        }

               stage('Deploy Redis and Application') {
            steps {
                withCredentials([string(credentialsId: 'redis-project-key', variable: 'PEM_KEY')]) {
                    dir('ansible') {
                        sh '''
                            set -eu
                            IP=$(cat "$WORKSPACE/redis_ip.txt")

                            KEY_FILE=$(mktemp)
                            trap 'rm -f "$KEY_FILE"' EXIT
                            printf '%s\\n' "$PEM_KEY" > "$KEY_FILE"
                            chmod 600 "$KEY_FILE"

                            cat > inventory.ini <<EOF
[redis_server]
$IP ansible_user=ubuntu ansible_ssh_private_key_file=$KEY_FILE ansible_ssh_common_args='-o StrictHostKeyChecking=no'
EOF

                            ansible-playbook -i inventory.ini playbook.yml
                        '''
                    }
                }
            }
        }

        stage('Deployment Summary') {
            steps {
                sh '''
                    echo "=================================="
                    echo "Redis project deployment completed"
                    echo "EC2 Public IP: $(cat "$WORKSPACE/redis_ip.txt")"
                    echo "App URL: http://$(cat "$WORKSPACE/redis_ip.txt"):5000"
                    echo "=================================="
                '''
            }
        }
    }

    post {
        success {
            echo 'SUCCESS: Infrastructure and application deployment completed!'
        }

        failure {
            echo 'FAILED: Check the failed stage logs before retrying.'
        }
    }
}