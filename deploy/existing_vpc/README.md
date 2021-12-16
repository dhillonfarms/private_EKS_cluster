# Existing VPC EKS Cluster Deployment in a Private EKS network

The following steps walks you through the deployment of this example

This example deploys a Basic EKS Cluster with Managed Node group with the following pre-requisites

- Existing VPC CIDR and VPC ID
- AWS Availability Zones
- Existing Private Subnet IDs from the above AZs
- Private Route Table
- Security Group ID of the Bastion or Cloud9 host

# How to Deploy

## Prerequisites:

Ensure that you have installed the following tools in your Mac or Windows Laptop before start working with this module and run Terraform Plan and Apply

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [aws-iam-authenticator](https://docs.aws.amazon.com/eks/latest/userguide/install-aws-iam-authenticator.html)
3. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
4. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)

## Deployment Steps

#### Step1: Clone the repo using the command below

```shell
git clone https://github.com/jvargh/eks-tf-accelerator-3.0.git
```

#### Step2: Run Terraform INIT

to initialize a working directory with configuration files

```shell
cd deploy/existing_vpc/
terraform init
```

#### Step3: Run Terraform PLAN

to verify the resources created by this execution

```shell
export AWS_REGION="us-east-1"   # Select your own region
terraform plan
```

#### Step4: Enable eks

to create resources. Ensure adding Bastion or Cloud9 Security Group to EKS Cluster Security Group at this point

```shell
create_eks = true
```

#### Step5: Terraform APPLY

to create resources

```shell
terraform apply
```

Enter `yes` to apply

#### Step6: Enable vpc_endpoints, managed_node-groups

to create resources

```shell
create_vpc_endpoints=true (with terraform apply), following which enable_managed_nodegroups=true (with terraform apply)
```


### Configure kubectl and test cluster

EKS Cluster details can be extracted from terraform output or from AWS Console to get the name of cluster. This following command used to update the `kubeconfig` in your local machine where you run kubectl commands to interact with your EKS Cluster.

#### Step5: Run update-kubeconfig command.

`~/.kube/config` file gets updated with cluster details and certificate from the below command

$ aws eks --region us-east-1 update-kubeconfig --name `<cluster-name>`

#### Step6: List all the worker nodes by running the command below

$ kubectl get nodes

#### Step7: List all the pods running in kube-system namespace

$ kubectl get pods -n kube-system

# How to Destroy

```shell
cd deploy/existing_vpc/
terraform destroy
```
