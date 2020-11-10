# data.world-nasa
This is an example Spark job that runs in AWS EMR. It utilizes the following technologies
- Spark
- Scala
- Gradle
- AWS EMR
- Terraform

There are two main sections in this project: the EMR infrastructure as code and the Spark job jar itself.
## Spark Job Jar
To set up the the jar, go to the data.world-nasa main directory and run
`gradle build`

The jar will then be located under `app/build/libs/app.jar`.

If you want to run this job in EMR, 
- Upoad app.jar into an S3 bucket. Let's assume it is called s3-bucket-name 
- SSH into the parent node and simply run `spark-submit --class nasa.App s3a://s3-bucket-name/app.jar

## Terraform for AWS EMR
To get it up and running, go into `aws/terraform` directory and run 

`terraform apply`

When you want your code to be destroyed, run `terraform destroy`.

This project sets up appropriate VPC, IGW, subnets, SSH keys, EMR cluster, and opens up the EMR cluster to SSH from my IP + to access Spark History UI.