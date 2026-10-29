pipeline {
    agent any

    // Jenkins UI: "Build with Parameters" -> choose ACTION -> Build
    parameters {
        choice(
            name: 'ACTION',
            choices: ['apply', 'destroy'],
            description: 'apply = create infra and deploy the app. destroy = delete ALL the AWS infrastructure.'
        )
    }

    stages {
        stage('Clone Repository') {
            steps {
                git branch: 'main',
                    url: 'https://github.com/bhumi262/redis-final-project.git'
            }
        }

        // Needed for BOTH apply and destroy (connects to the S3 state)
        stage('Terraform Init') {
            steps {
                dir('terraform') {
                    sh 'terraform init'
                }
            }
        }

        // Needed for BOTH apply and destroy (Terraform variables)
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

        // ===================== DESTROY FLOW =====================
        stage('Terraform Plan (Destroy)') {
            when { expression { params.ACTION == 'destroy' } }
            steps {
                dir('terraform') {
                    sh '''
                        set -eu
                        SSH_CIDR=$(cat "$WORKSPACE/ssh_allowed_cidr.txt")
                        terraform plan -destroy -var="ssh_allowed_cidr=$SSH_CIDR" -var="app_allowed_cidr=$SSH_CIDR"
                    '''
                }
            }
        }

        stage('Confirm Destroy') {
            when { expression { params.ACTION == 'destroy' } }
            steps {
                timeout(time: 10, unit: 'MINUTES') {
                    input message: 'This will DELETE the whole AWS infrastructure (EC2, VPC, Security Group, IAM role). Continue?',
                          ok: 'Yes, destroy everything'
                }
            }
        }

        stage('Terraform Destroy') {
            when { expression { params.ACTION == 'destroy' } }
            steps {
                dir('terraform') {
                    sh '''
                        set -eu
                        SSH_CIDR=$(cat "$WORKSPACE/ssh_allowed_cidr.txt")
                        terraform destroy -auto-approve -var="ssh_allowed_cidr=$SSH_CIDR" -var="app_allowed_cidr=$SSH_CIDR"
                        rm -f "$WORKSPACE/redis_ip.txt"
                        echo "All AWS resources created by Terraform are destroyed."
                    '''
                }
            }
        }

        // ===================== APPLY FLOW =====================
        stage('Terraform Plan') {
            when { expression { params.ACTION == 'apply' } }
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
            when { expression { params.ACTION == 'apply' } }
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
            when { expression { params.ACTION == 'apply' } }
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
            when { expression { params.ACTION == 'apply' } }
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
            when { expression { params.ACTION == 'apply' } }
            steps {
                dir('ansible') {
                    sh '''
                        set -eu
                        IP=$(cat "$WORKSPACE/redis_ip.txt")

                        cat > inventory.ini <<EOF
[redis_server]
$IP ansible_user=ubuntu ansible_ssh_common_args='-o StrictHostKeyChecking=no'
EOF

                        echo "Ansible inventory prepared."
                    '''
                }
            }
        }

        // SSH key comes from the Jenkins credential "redis-pem" (Secret text, base64 of the .pem)
        stage('Deploy Redis and Application') {
            when { expression { params.ACTION == 'apply' } }
            steps {
                withCredentials([string(credentialsId: 'redis-pem', variable: 'PEM_KEY')]) {
                    dir('ansible') {
                        sh '''
                            set -eu
                            IP=$(cat "$WORKSPACE/redis_ip.txt")

                            KEY_FILE=$(mktemp)
                            trap 'rm -f "$KEY_FILE"' EXIT
                            printf '%s' "$PEM_KEY" | tr -d '[:space:]' | base64 -d > "$KEY_FILE"
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
            when { expression { params.ACTION == 'apply' } }
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
            echo "SUCCESS: ACTION '${params.ACTION}' completed!"
        }

        failure {
            echo "FAILED: ACTION '${params.ACTION}'. Check the failed stage logs before retrying."
        }

        aborted {
            echo "ABORTED: ACTION '${params.ACTION}' was not confirmed or was stopped."
        }
    }
}