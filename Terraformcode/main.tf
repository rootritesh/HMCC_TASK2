provider "aws" {
  region = "ap-south-1"
}



resource "aws_security_group" "http_ssh_protocol" {
  name        = "allow_http_ssh_NFS"
  description = "Allow http and ssh inbound traffic"
  vpc_id      = "vpc-4bc5d123"


  ingress {
    description = "HTTP from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "ssh from VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "tcp from VPC"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
ingress {
    description = "allow nfs"
    from_port   = 2049  
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }


  tags = {
    Name = "allow_protocols"
  }
}

resource "aws_efs_file_system" "efs" {
  creation_token = "my-product"
  tags = {
    Name = "myefs"
  }
}

resource "aws_efs_mount_target" "alpha" {
  depends_on = [
    aws_efs_file_system.efs,
    aws_security_group.http_ssh_protocol
  ]
  file_system_id = aws_efs_file_system.efs.id
  security_groups = [aws_security_group.http_ssh_protocol.id]
  subnet_id      = aws_instance.webos.subnet_id
}

resource "tls_private_key" "key_ssh" {
  depends_on = [aws_security_group.http_ssh_protocol,


  ]
   algorithm  = "RSA"
  rsa_bits   = 4096
}

resource "aws_key_pair" "key2" {
  key_name   = "mykeys"
  public_key = tls_private_key.key_ssh.public_key_openssh
}
output "key_ssh" {
  value = tls_private_key.key_ssh.private_key_pem
}

resource "local_file" "save_key" {
  depends_on=[aws_key_pair.key2]
    content     = tls_private_key.key_ssh.private_key_pem
    filename = "mykeys.pem"
}





resource "aws_instance"  "webos"  {
     depends_on = [
       aws_key_pair.key2,
       tls_private_key.key_ssh,
       local_file.save_key,
       aws_efs_file_system.efs
  ]
  ami           =  "ami-0b5bff6d9495eff69"
  instance_type     =  "t2.micro"
  key_name          =  "mykeys"
  security_groups =  [  "allow_http_ssh_NFS"  ]



  tags  =  {
    Name  =  "WebOSec2"
  }
}


resource "null_resource" "null1"  {


    depends_on = [
      aws_instance.webos,
      local_file.save_key,
      aws_efs_mount_target.alpha,
  
  ]


 connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.key_ssh.private_key_pem
    host     = aws_instance.webos.public_ip
  }


  provisioner "remote-exec" {
    inline = [
      "sudo git clone https://github.com/rootritesh/HMCC_TASK2.git /var/www/html",
      "sudo wget -O /etc/yum.repos.d/jenkins.repo http://pkg.jenkins.io/redhat-stable/jenkins.repo",
      "sudo rpm --import http://pkg.jenkins.io/redhat-stable/jenkins.io.key",
      "sudo yum update -y",
      "sudo yum remove java-1.7.0-openjdk -y",
      "sudo yum install httpd git amazon-efs-utils java-1.8.0-openjdk jenkins -y",
      "sudo service jenkins start",
      "sudo service httpd start",
      "sudo mount -t efs -o tls ${aws_efs_file_system.efs.id}:/ /var/www/html",
      "sudo cat /var/lib/jenkins/secrets/initialAdminPassword",
    ]
  }
}

resource "null_resource" "null2"  {
  provisioner "local-exec" {
      command = "git clone https://github.com/rootritesh/HMCC_TASK2.git ./gitcode"
    }
}    



resource "aws_s3_bucket" "b1" {
  bucket = "codeofweb"
  acl    = "public-read"
  versioning {
  enabled = true
}


  tags = {
    Name        = "HMCCTASk2"
    Environment = "Dev"
  }
}


resource "aws_s3_bucket_object" "obj1" {
  key = "welcome.jpg"
bucket = aws_s3_bucket.b1.id
source = "./gitcode/welcome.jpg"
acl="public-read"
}

resource "aws_cloudfront_distribution" "cloudfront1" {
   depends_on = [
     aws_s3_bucket.b1,
     null_resource.null1,
  ]


    origin {
        domain_name = "codeofweb.s3.amazonaws.com"
        origin_id = aws_s3_bucket.b1.id



        custom_origin_config {
            http_port = 80
            https_port = 80
            origin_protocol_policy = "match-viewer"
            origin_ssl_protocols = ["TLSv1", "TLSv1.1", "TLSv1.2"]
        }
    }


    enabled = true



    default_cache_behavior {
        allowed_methods = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
        cached_methods = ["GET", "HEAD"]
        target_origin_id = aws_s3_bucket.b1.id


        forwarded_values {
            query_string = false


            cookies {
               forward = "none"
            }
        }
        viewer_protocol_policy = "allow-all"
        min_ttl = 0
        default_ttl = 3600
        max_ttl = 86400
    }


    restrictions {
        geo_restriction {


            restriction_type = "none"
        }
    }


    viewer_certificate {
        cloudfront_default_certificate = true
    }
}


resource "null_resource" "null4"  {
  provisioner "local-exec" {
      command = "echo  ${aws_cloudfront_distribution.cloudfront1.domain_name
} > cloudfrontURL.txt"
    }
}