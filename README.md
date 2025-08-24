# Adobe Security – Take-Home Exercise

**Role target:** Product Security Engineer – Edge / WAF Focus
**Estimated Effort:** Approximately **16 focused hours** (this may vary based on individual experience)
**Deadline:** Submit within **120 hours** (5 days) of receiving the repo invite

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

### 1 – Reusable WAF Module

* Create a reusable infrastructure as code module (e.g., Terraform module or CDK construct) named `edge_waf`.
* This module should provision an **AWS WAF v2 WebACL**.
* The module must allow associating the WebACL with the front-door resource (ALB ARN or CloudFront Distribution ID created in Step 0) via **one variable input** passed to the module.
* Configure the WebACL within the module to:
    * Enable **at least two** relevant AWS-managed rule groups (e.g., `AWSManagedRulesCommonRuleSet`, `AWSManagedRulesSQLiRuleSet`).
    * Include **at least one custom rule** designed specifically to block the known Juice Shop SQL injection payload (`' OR 1=1--`) when submitted to the `/rest/products/search` path.

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

### 6 – README / Runbook

* Create a concise `README.md` file (target ≤ 2 pages) in the root of your repository.
* It must include:
    * **Prerequisites:** Any tools, accounts, or specific versions needed to run your code.
    * **Setup:** Clear steps for configuring any required variables (e.g., AWS region, account ID if needed).
    * **Deployment:** Instructions on how to deploy the entire infrastructure (e.g., `make deploy`, `terraform apply`, `cdk deploy`). Aim for a straightforward process. **Target deployment time:** ~20 minutes (may vary based on AWS).
    * **Usage:** How to run the `push_block` script (Deliverable 3) with examples.
    * **Verification:** How to run the smoke test (Deliverable 4) and interpret its output.
    * **KPI Query:** How to execute the Athena query (Deliverable 5) and where to view the results (e.g., AWS Console).
    * **Evidence:** Include or reference the location of required outputs like smoke test results and KPI query results (e.g., link to files in a `/results` directory or embed directly if concise).

---

## Stretch Goals (Optional)

These are not required but demonstrate deeper expertise:

* Implement the WAF WebACL deployment using **AWS Firewall Manager** for centralized policy management.
* Add **unit tests** for your infrastructure code using relevant frameworks (e.g., Terratest for Terraform, `pytest-assert-utils` or snapshot testing for CDK).
* Export the calculated KPI metrics (Deliverable 5) to **Amazon CloudWatch Metrics** and create a simple **CloudWatch Dashboard** displaying the `%blocked` rate.

---

## 3. Submission Process

1.  Create a **private** GitHub repository for your solution. Invite the specified Adobe contact(s) as collaborators.
2.  **Commit your code early and often.** We value seeing your thought process and development history through the git log.
3.  Ensure all code, configurations, workflows, and documentation (`README.md`) are pushed to the repository.
4.  Include evidence of successful execution:
    * Place outputs from your smoke test (Deliverable 4) and KPI query (Deliverable 5) either in a dedicated `/results` directory or embed them clearly within your `README.md`.
    * If you used AI assistance (like ChatGPT, Copilot, etc.), please include a brief summary or examples of key prompts used in your `README.md` or a separate file.
