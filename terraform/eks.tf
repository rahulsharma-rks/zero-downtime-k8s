module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.26.0"

  name               = var.cluster_name
  kubernetes_version = "1.36"

  endpoint_public_access = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  enable_cluster_creator_admin_permissions = true

  addons = {
    vpc-cni = {
      most_recent    = true
      before_compute = true
    }

    kube-proxy = {
      most_recent    = true
      before_compute = true
    }

    coredns = {
      most_recent    = true
      before_compute = true
    }

    eks-pod-identity-agent = {
      most_recent    = true
      before_compute = true
    }
  }
  eks_managed_node_groups = {
    default = {
      name = "zero-downtime-ng"

      instance_types = ["t3.small"]

      min_size     = 2
      max_size     = 2
      desired_size = 2

      capacity_type = "ON_DEMAND"

      disk_size = 20

      labels = {
        Project = var.project_name
      }
    }
  }

  tags = {
    Project = var.project_name
  }
}
