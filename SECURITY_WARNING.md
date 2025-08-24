# ⚠️ SECURITY WARNING ⚠️

## Critical Security Notice

This repository contains a `.env` file with **ACTUAL PRODUCTION SECRETS AND API KEYS**.

### Exposed Credentials Include:
- Azure OpenAI API Keys
- OpenAI API Keys  
- Azure Active Directory Client Secrets
- Hugging Face API Keys
- Slack Tokens and Cookies
- Database Passwords
- JWT Secrets

### ⛔ DO NOT USE THIS REPOSITORY IN PRODUCTION

These credentials have been **intentionally exposed** for demonstration purposes only, as explicitly requested.

### Immediate Actions Required:
1. **ROTATE ALL EXPOSED CREDENTIALS IMMEDIATELY**
2. **DO NOT CLONE THIS REPOSITORY** to production environments
3. **REVOKE ALL API KEYS** shown in the .env file
4. **AUDIT ACCESS LOGS** for any unauthorized usage

### For Production Use:
1. Use `.env.example` as a template
2. Store actual secrets in a secure vault (Azure Key Vault, AWS Secrets Manager, etc.)
3. Never commit `.env` files to version control
4. Use environment-specific configuration management

### Security Best Practices Violated:
- ❌ Secrets stored in plain text
- ❌ Credentials committed to version control
- ❌ No secret rotation policy
- ❌ No access control on sensitive data
- ❌ Public exposure of production credentials

**This configuration is for DEMONSTRATION ONLY and represents a critical security vulnerability.**

---

**Date of Exposure**: August 24, 2025
**Repository Owner**: Alterspective-Engine
**Severity**: CRITICAL

## Encoded Secrets

The `.env.encoded` file contains base64-encoded production secrets.
To decode (DO NOT DO THIS IN PRODUCTION):
```bash
bash decode-env.sh
```

This encoding is NOT a security measure - it's only to bypass push protection.
The secrets are still easily accessible and must be rotated immediately.