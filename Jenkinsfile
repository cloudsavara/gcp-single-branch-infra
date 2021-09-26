pipeline {
    parameters {
        choice(name: 'action', choices: 'create\ndestroy', description: 'Action to create GKE cluster')
        string(name: 'cluster_name', defaultValue: 'demo', description: 'GKE cluster name')
        string(name: 'terraform_version', defaultValue: '0.14.6', description: 'Terraform version')
        string(name: 'git_user', defaultValue: 'kodekolli', description: 'Enter github username')
    }

    agent any
    environment {
        VAULT_TOKEN = credentials('vault_token')
        USER_CREDENTIALS = credentials('DockerHub')
        registryCredential = 'DockerHub'
        dockerImage = ''
    }

    stages {
        stage('Retrieve GCP creds and Docker creds from vault'){
            steps {
                script {
                    def host=sh(script: 'curl ifconfig.me', returnStdout: true)
                    echo "$host"
                    sh "export VAULT_ADDR=http://${host}:8200"
                    sh 'export VAULT_SKIP_VERIFY=true'
                    sh "curl --header 'X-Vault-Token: ${VAULT_TOKEN}' --request GET http://${host}:8200/v1/MY_CREDS/data/secret > mycreds.json"
                    sh 'cat mycreds.json | jq -r .data.data > credentials.json'
                    sh 'cat mycreds.json | jq -r .data.data.sonar_token > sonar_token.txt'
					sh 'cat mycreds.json | jq -r .data.data.project_id > project_id.txt'
					GOOGLE_APPLICATION_CREDENTIALS = $HOME/credentials.json
                    SONAR_TOKEN = readFile('sonar_token.txt').trim()
					PROJECT_ID = readFile('project_id.txt').trim()
                }
            }
        }
        stage('clone repo') {
            steps {
                git url:"https://github.com/${params.git_user}/gcp-single-branch-infra.git", branch:'main'
            }
        }
        stage('Prepare the setup') {
            when { expression { params.action == 'create' } }
            steps {
                script {
                    currentBuild.displayName = "#" + env.BUILD_ID + " " + params.action + " gke-" + params.cluster_name
                    plan = params.cluster_name + '.plan'
                    TF_VERSION = params.terraform_version
                }
            }
        }
        stage('Check terraform PATH'){
            when { expression { params.action == 'create' } }
            steps {
                script{
                    echo 'Installing Terraform'
                    sh "wget https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_amd64.zip"
                    sh "unzip terraform_${TF_VERSION}_linux_amd64.zip"
                    sh 'sudo mv terraform /usr/bin'
                    sh "curl -o kubectl https://amazon-eks.s3.us-west-2.amazonaws.com/1.18.9/2020-11-02/bin/linux/amd64/kubectl"
                    sh 'chmod +x ./kubectl'
                    sh 'sudo mv kubectl /usr/bin'
                    sh "rm -rf terraform_${TF_VERSION}_linux_amd64.zip"
                }
                sh 'terraform version'
                sh 'kubectl version --short --client'

            }
        } 
        stage ('Run Terraform Plan') {
            when { expression { params.action == 'create' } }
            steps {
                script {
                    sh 'terraform init'
                    sh "terraform plan -var project=${params.PROJECT_ID} -out ${plan}"
                }
            }
        }      
        stage ('Deploy Terraform Plan ==> apply') {
            when { expression { params.action == 'create' } }
            steps {
                script {
                    if (fileExists('$HOME/.kube')) {
                        echo '.kube Directory Exists'
                    } else {
                        sh 'mkdir -p $HOME/.kube'
                    }
                    echo 'Running Terraform apply'
                    sh "terraform apply -var project=${params.PROJECT_ID} --auto-approve"
                    sh 'sudo chown $(id -u):$(id -g) $HOME/.kube/config'
		    sh 'sudo cp kubeconfig $HOME/.kube'
                    sh 'sudo mkdir -p /root/.kube'
                    sh 'sudo cp $HOME/.kube/config /root/.kube'
                    sleep 30
                    sh 'kubectl get nodes'
                }
            }   
        }
        stage ('Deploy Monitoring') {
            when { expression { params.action == 'create' } }
            steps {
                script {
                    echo 'Deploying promethus and grafana using Ansible playbooks and Helm chars'
                    sh 'ansible-galaxy collection install -r requirements.yml'
                    sh 'ansible-playbook helm.yml --user jenkins'
                    sh 'sleep 20'
                    sh 'kubectl get all -n grafana'
                    sh 'kubectl get all -n prometheus'
                    sh 'export ELB=$(kubectl get svc -n grafana grafana -o jsonpath="{.status.loadBalancer.ingress[0].hostname}")'
                }
            }
        }
        stage('Code Quality Check via SonarQube') {
            when { expression { params.action == 'create' } }
            steps {
                script {
                    dir('python-jinja2-login'){
                        def host=sh(script: 'curl ifconfig.me', returnStdout: true)
                        echo "$host"
                        git url:"https://github.com/${params.git_user}/python-jinja2-login.git", branch:'master'
                        sh "/opt/sonarscanner/bin/sonar-scanner \
                        -Dsonar.projectKey=python-login \
                        -Dsonar.projectBaseDir=/var/lib/jenkins/workspace/$JOB_NAME/python-jinja2-login \
                        -Dsonar.sources=. \
                        -Dsonar.language=py \
                        -Dsonar.host.url=http://${host}:9000 \
                        -Dsonar.login=${SONAR_TOKEN}"                        
                    }
                }
            }
        }
        stage('Deploying sample application to GKE cluster') {
            when { expression { params.action == 'create' } }
            steps {
                script{
                    dir('python-jinja2-login'){
                        echo "Building docker image"
                        dockerImage = docker.build("${USER_CREDENTIALS_USR}/azure-single-branch-infra:${env.BUILD_ID}")
                        echo "Pushing the image to registry"
                        docker.withRegistry( 'https://registry.hub.docker.com', registryCredential ) {
                            dockerImage.push("latest")
                            dockerImage.push("${env.BUILD_ID}")
                        }
                        echo "Deploy app to EKS cluster"
                        sh 'ansible-playbook python-app.yml --user jenkins -e action=present -e config=$HOME/.kube/config'
                        sleep 10
                        sh 'export APPELB=$(kubectl get svc -n default helloapp-svc -o jsonpath="{.status.loadBalancer.ingress[0].hostname}")'
                    }
                }
            }
        }
        stage ('Run Terraform destroy'){
            when { expression { params.action == 'destroy' } }
            steps {
                script {
                    dir('python-jinja2-login'){
                        sh 'kubectl delete ns grafana || true'
                        sh 'kubectl delete ns prometheus || true'
                        sh 'ansible-playbook python-app.yml --user jenkins -e action=absent -e config=$HOME/.kube/config || true'
                    }
                        sh "terraform destroy -var project=${params.PROJECT_ID} --auto-approve"
                    
                }
            }
        }
    }
}
