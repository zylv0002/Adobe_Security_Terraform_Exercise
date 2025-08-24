# Security Platform Engineering Challenge

**Role:** Senior Security Platform Engineer  
**Timeline:** 5 calendar days  
**Deliverable:** Working solution with documentation

---

## Business Context

Adobe's product teams are struggling with web application security. Each team manages their own WAF rules across AWS and Azure, leading to:
- Inconsistent security postures
- Delayed responses to vulnerabilities  
- High operational overhead
- Frequent false positives causing customer impact
- No visibility into what rules are deployed where

Last month, a critical SQL injection vulnerability affected 12 services. Each team took 3-5 days to deploy patches independently, and two teams accidentally blocked legitimate traffic, causing $200K in lost revenue.

---

## The Problem to Solve

Design and build a platform that enables product teams to protect their web applications consistently across AWS WAF and Azure WAF, while maintaining Adobe's security standards.

### Business Requirements

**Security Requirements:**
- When new vulnerabilities are discovered, patches must be deployable across all affected services within 4 hours
- False positive rate must stay below 0.1% 
- All changes must be auditable for compliance
- Security team needs ability to push emergency blocks

**Developer Requirements:**
- Product teams need self-service capabilities
- Changes should be testable before production
- Rollback must be possible within 1 minute
- No deep WAF expertise should be required

**Operational Requirements:**
- Support 50+ services across 2 cloud providers
- Handle 100K+ requests per second aggregate traffic
- Maintain 99.9% availability
- Cost-efficient (minimize WAF rule evaluations)

### Constraints

- Must work with existing AWS WAF and Azure Front Door WAF
- Cannot modify application code
- Teams use different deployment tools (Terraform, CloudFormation, ARM)
- Limited to 5 days development time
- Must use free tier or minimal cloud spend for demo

### Success Criteria

Your solution will be evaluated on:
1. How well it solves the stated problems
2. Architecture decisions and trade-offs
3. Production readiness
4. Developer experience
5. Operational sustainability

---

## Deliverables

### 1. Working Solution
- Demonstrate the core capability
- Handle at least 2 example services
- Show both AWS and Azure integration
- Include automated deployment

### 2. Architecture Documentation
- System design and rationale
- Key decisions and trade-offs
- Data models and flows
- Security considerations
- Scale and performance approach

### 3. Demo
- 5-minute video or live demo showing:
  - Service onboarding
  - Vulnerability response
  - Rollback scenario
  - Multi-cloud deployment

### 4. Runbook
- How to operate your solution
- How to extend it
- Known limitations
- Future improvements

---

## Evaluation Focus

We're looking for:
- **Problem decomposition** - How did you break down the problem?
- **Architecture thinking** - What patterns and principles did you apply?
- **Trade-off analysis** - What did you optimize for and why?
- **Production mindset** - How did you handle failures, monitoring, operations?
- **Simplicity** - Did you avoid over-engineering?

---

## What We're NOT Looking For

- Perfect code coverage
- Beautiful UIs
- Every possible feature
- Proprietary Adobe information

---

## Advisory Feed Format

Your solution should be able to consume security advisories in this format:

```json
{
  "advisories": [
    {
      "id": "ADV-2025-001",
      "description": "SQL injection in login endpoints",
      "indicator": "pattern:('.+--)|union.*select",
      "severity": "critical",
      "affected_paths": ["/login", "/auth"],
      "recommended_action": "block"
    }
  ]
}
```

---

## FAQ

**Q: What technology should I use?**  
A: Your choice. Pick what allows you to best demonstrate the solution.

**Q: How much should I build vs. document?**  
A: Build enough to prove the concept works. Document the rest.

**Q: Can I use AI tools?**  
A: Yes, but be prepared to explain your architectural decisions.

**Q: What if I can't access both clouds?**  
A: Use mocks/stubs but show how real integration would work.

---

## Submission

- GitHub repository with your solution
- README with setup instructions
- Architecture documentation
- Demo video or instructions for live demo

**Submit to:** [submission-email]  
**Deadline:** 5 days from receipt

---

*We're interested in how you think about and solve this problem. There's no single right answer.*
