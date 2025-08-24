#!/bin/bash
# WARNING: This script decodes the .env file containing production secrets
# DO NOT RUN THIS IN PRODUCTION ENVIRONMENTS

if [ -f ".env.encoded" ]; then
    echo "⚠️  WARNING: Decoding file containing production secrets..."
    base64 -d .env.encoded > .env
    echo "✅ .env file decoded successfully"
    echo "⛔ CRITICAL: This file contains real API keys and secrets!"
    echo "   Please rotate all credentials immediately!"
else
    echo "❌ Error: .env.encoded file not found"
    exit 1
fi