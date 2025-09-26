# Adobe Security – Take-Home Exercise

**target:**  This is a production-level exercise designed by Adobe’s Security Engineer team simulating the responsibilities of a
mid-level security engineer focused on Infrastructure-as-Code (IaC) for rapid, repeatable deployments

---

## 1. Scenario

A new public-facing web application—**OWASP Juice Shop**—is scheduled to launch next week. Before the DNS cut-over, the Product Security team needs confirmation that the proposed edge security configuration meets the following key criteria:

1.  **Repeatable:** The core security guardrails can be applied to any future service with minimal effort (e.g., within minutes) via infrastructure as code.
2.  **Rapidly Tunable:** The security team can deploy an emergency WAF rule (e.g., blocking a newly discovered malicious pattern) in under **30 minutes**.
3.  **Measurable:** There is a clear Key Performance Indicator (KPI) demonstrating the effectiveness of the edge protection, which can be used for monitoring and tuning.

---

## 2. Deliverables

### 0 – Service & Front Door

* Deploy the **OWASP Juice Shop** application (using the public container image or using EC2 instead of docker)
    * **Deployment Target:** Use **AWS ECS Fargate** or similar, EKS, Fargate, Lambda or even EC2 
* Expose the application publicly using either an **AWS Application Load Balancer (ALB)** *or* **Amazon CloudFront** distribution.
* Define and manage **all** AWS infrastructure components using **Terraform** *or* **AWS CDK**.

### My actions:
	1. Initiate a VPC with public and private subnets.
	2. Placed compute resource (ECS Fargate) in the private subnet and an Application Load Balancer (ALB) in the public subnet.
	3. Configured traffic to route through AWS WAF (Reusable WAF module named 'edge_waf', see ## Delivery #1) before reaching the ALB.
	4. Deployed the ALB with a DNS name: 'juice-waf-dev-alb-1347322202.us-east-1.elb.amazonaws.com'.
	5. Set ALB ingress rules to allow all HTTP (port 80) traffic and forward it to a Target Group on port 3000.
	6. The Target Group directs traffic to the ECS Fargate service, which hosts the OWASP Juice Shop application using the container image (bkimminich/juice-shop).
### I learned that:
	1. WAF is a managed service: I realized that WAF is a managed service that is not deployed within the VPC I created.
	2. I initially mixed up the security group and the target group. After some research, I now understand that a security group acts as a firewall that's attached to other resources to control network traffic (at the network layer), while a target group is a resource that routes traffic to the correct destinations, which is the ECS Fargate in this case.


### 1 – Reusable WAF Module

* Create a reusable infrastructure as code module (e.g., Terraform module or CDK construct) named `edge_waf`.
* This module should provision an **AWS WAF v2 WebACL**.
* The module must allow associating the WebACL with the front-door resource (ALB ARN or CloudFront Distribution ID created in Step 0) via **one variable input** passed to the module.
* Configure the WebACL within the module to:
    * Enable **at least two** relevant AWS-managed rule groups (e.g., `AWSManagedRulesCommonRuleSet`, `AWSManagedRulesSQLiRuleSet`).
    * Include **at least one custom rule** designed specifically to block the known Juice Shop SQL injection payload (`' OR 1=1--`) when submitted to the `/rest/products/search` path.
 
### My actions:
	1. Configured a reusable AWS WAF v2 WebACL Module (edge_waf).
	2. Associated the WAF module with Delivery #0 by accepting the ALB ARN as an input variable.
	3. Declared two AWS managed rule sets, AWSManagedRulesCommonRuleSet with priority=10 and AWSManagedRulesSQLiRuleSet with priority=20
	4. Created a custom rule with priority=30 that blocks the SQLi payload "' OR 1=1--" when submitted to the /rest/products/search path.
### I learned that:
    1. WAF priority defines the sequence in which rule sets are evaluated (from lower to higher).

### 2 – CI/CD Guardrail

* Implement a simple CI/CD pipeline using **GitHub Actions** (`.github/workflows/edge-ci.yml`).
* The workflow should trigger on Pull Requests targeting the `main` branch and perform the following:
    * Run a static analysis security tool on your IaC code (`tfsec` for Terraform *or* `cdk-nag` for CDK).
    * Generate an infrastructure plan (`terraform plan` or `cdk diff`) and post it as a comment on the Pull Request.
    * *(Conceptual)* Include a step that would require manual reviewer approval before allowing an `apply` / `deploy` action (the actual deployment is done manually for this exercise, but the workflow should show the gate).

### 3 – Rapid-Mitigation Script

* Develop a command-line script (`push_block.py`, `push_block.sh`, or similar) for quickly adding block rules to the deployed WAF WebACL.
* The script must:
    * Accept either an IP address/CIDR range *or* a URI string/regex pattern as input.
    * Create or update a **WAF rule** within the WebACL to **block** requests matching the provided input.
    * Complete its execution (creating/updating the rule via AWS API) in **less than 60 seconds** wall time.

### 4 – Smoke Test

* Provide a simple way to verify the WAF rules are functioning correctly. This can be a script (e.g., Python, Bash using `curl`) or a Postman collection.
* The test should:
    * Send a benign request (e.g., GET `/`) to the Juice Shop URL and expect a `200 OK` response.
    * Send a request containing the specific SQL injection payload (`' OR 1=1--`) to the `/rest/products/search` path and expect a `403 Forbidden` response (indicating it was blocked by the WAF).
    * Clearly print or display the results of both tests (success/failure and status codes).

### 5 – Log Pipeline & KPI

* Configure **WAF logging** to send logs to **Amazon Kinesis Data Firehose**, delivering them to an **S3 bucket** within the same AWS account.
* Define an **AWS Athena table** that can query the WAF logs stored in the S3 bucket.
* Provide **one specific Athena SQL query** that calculates and returns the following metrics based on the WAF logs:
    * `total_requests` (Total requests processed by WAF)
    * `blocked_requests` (Count of requests blocked by WAF)
    * `percent_blocked` (Percentage of total requests that were blocked)
    * `top_5_attack_vectors` (The top 5 rule labels/names that triggered blocks, grouped by label)
* Include a brief explanation (≤ 200 words) in your README describing how monitoring this KPI (especially `%blocked` and `top_5_attack_vectors`) helps security teams tune rules, identify false positives, and potentially measure Mean Time To Respond (MTTR) for new threats.

### My actions:
	1. Configured the aws_kinesis_firehose_delivery_stream.
	2. Configured the logging configuration for the WAF. 
	3. Created Athena catalog for WAF logs, and prepared a SQL query that will calculate the highlighted KPIs (total_requests, blocked_requests and percent_blocked and top_5_attack_vectors). 
### I learned that:
	1. We can use jsonencode to generate the policy statement to minimize errors associated with hardcoding。
	2. We can assign actions s3:ListBucketMultipartUploads and s3:AbortMultipartUpload to Firehose roles to allow identify and clean up the interrupted upload to avoice additional cost.
	3. Based on the Principle of Least Privilege, read and write access should be separated by granting write access only to specific WAF resources.
    4. I have limited experience with firehose and Athena. By completd this delivery, I now know that firehose will help buffer, compress and categorize the log, instead of writing every single log directly into S3 bucket, which would save significant cost and boost performance.

---

## Stretch Goals (Optional)

These are not required but demonstrate deeper expertise:

* Implement the WAF WebACL deployment using **AWS Firewall Manager** for centralized policy management.
* Add **unit tests** for your infrastructure code using relevant frameworks (e.g., Terratest for Terraform, `pytest-assert-utils` or snapshot testing for CDK).
* Export the calculated KPI metrics (Deliverable 5) to **Amazon CloudWatch Metrics** and create a simple **CloudWatch Dashboard** displaying the `%blocked` rate.

---
