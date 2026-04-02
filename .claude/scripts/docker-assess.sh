#!/usr/bin/env bash
set -euo pipefail

# Detect project type and classify services
# Output: JSON with dockerizable and host-only services

PROJECT_DIR="${1:-.}"
cd "$PROJECT_DIR"

SERVICES='{"services":[],"host_services":[],"reasons":[]}'

# === DETECT BACKEND ===
if [ -f "composer.json" ]; then
  SERVICES=$(echo "$SERVICES" | jq '.services += [{"name":"php","type":"backend","preferred_port":8000,"range_start":8000,"range_end":8100,"docker":true}]')
  # Check if Laravel
  if grep -q '"laravel/framework"' composer.json 2>/dev/null; then
    SERVICES=$(echo "$SERVICES" | jq '.services += [{"name":"nginx","type":"webserver","preferred_port":80,"range_start":8080,"range_end":8180,"docker":true,"internal":true}]')
  fi
fi

if [ -f "package.json" ] && grep -qE '"express"|"fastify"|"koa"|"hapi"|"@nestjs"' package.json 2>/dev/null; then
  SERVICES=$(echo "$SERVICES" | jq '.services += [{"name":"node","type":"backend","preferred_port":3001,"range_start":3001,"range_end":3100,"docker":true}]')
fi

if [ -f "requirements.txt" ] || [ -f "pyproject.toml" ] || [ -f "Pipfile" ]; then
  SERVICES=$(echo "$SERVICES" | jq '.services += [{"name":"python","type":"backend","preferred_port":8000,"range_start":8000,"range_end":8100,"docker":true}]')
  # Check if FastAPI/Flask/Django
  if grep -qE 'fastapi|flask|django' requirements.txt pyproject.toml 2>/dev/null; then
    true  # already added python service
  fi
fi

# === DETECT FRONTEND ===
if [ -f "package.json" ] && grep -qE '"next"|"react-scripts"|"vite"|"nuxt"|"@vue"' package.json 2>/dev/null; then
  SERVICES=$(echo "$SERVICES" | jq '.services += [{"name":"frontend","type":"frontend","preferred_port":3000,"range_start":3000,"range_end":3100,"docker":true}]')
fi

# Subdirectory frontend
if [ -f "frontend/package.json" ] 2>/dev/null; then
  SERVICES=$(echo "$SERVICES" | jq '.services += [{"name":"frontend","type":"frontend","preferred_port":3000,"range_start":3000,"range_end":3100,"docker":true}]')
fi

# === DETECT DATABASE ===
if grep -rqiE "mysql|mariadb" .env docker-compose.yml composer.json package.json requirements.txt 2>/dev/null; then
  SERVICES=$(echo "$SERVICES" | jq '.services += [{"name":"mysql","type":"database","preferred_port":3306,"range_start":3306,"range_end":3400,"docker":true}]')
fi

if grep -rqiE "postgres|pgsql|pg_connect" .env docker-compose.yml composer.json package.json requirements.txt 2>/dev/null; then
  SERVICES=$(echo "$SERVICES" | jq '.services += [{"name":"postgresql","type":"database","preferred_port":5432,"range_start":5432,"range_end":5500,"docker":true}]')
fi

if grep -rqiE "redis" .env docker-compose.yml composer.json package.json requirements.txt 2>/dev/null; then
  SERVICES=$(echo "$SERVICES" | jq '.services += [{"name":"redis","type":"cache","preferred_port":6379,"range_start":6379,"range_end":6400,"docker":true}]')
fi

if grep -rqiE "mongo" .env docker-compose.yml package.json requirements.txt 2>/dev/null; then
  SERVICES=$(echo "$SERVICES" | jq '.services += [{"name":"mongodb","type":"database","preferred_port":27017,"range_start":27017,"range_end":27100,"docker":true}]')
fi

# === DETECT HOST-ONLY SERVICES ===

# MS Office Add-in: manifest.xml presence
if find . -maxdepth 2 -name "manifest*.xml" 2>/dev/null | head -1 | grep -q .; then
  SERVICES=$(echo "$SERVICES" | jq '.host_services += [{"name":"office-addin","type":"addin","preferred_port":3000,"range_start":3000,"range_end":3100}]')
  SERVICES=$(echo "$SERVICES" | jq '.reasons += ["office-addin: Office sideload requires localhost access outside Docker — manifest validation and taskpane serve must run on host"]')
fi

# Electron: main process detection
if [ -f "package.json" ] && grep -q '"electron"' package.json 2>/dev/null; then
  SERVICES=$(echo "$SERVICES" | jq '.host_services += [{"name":"electron","type":"desktop","preferred_port":0}]')
  SERVICES=$(echo "$SERVICES" | jq '.reasons += ["electron: Desktop GUI requires host display server — build process can be Dockerized but runtime/testing needs host"]')
fi

# React Native: mobile
if [ -f "package.json" ] && grep -q '"react-native"' package.json 2>/dev/null; then
  SERVICES=$(echo "$SERVICES" | jq '.host_services += [{"name":"react-native","type":"mobile","preferred_port":8081,"range_start":8081,"range_end":8100}]')
  SERVICES=$(echo "$SERVICES" | jq '.reasons += ["react-native: Metro bundler and device emulator require host access — API backend can be Dockerized"]')
fi

# Flutter: mobile
if [ -f "pubspec.yaml" ]; then
  SERVICES=$(echo "$SERVICES" | jq '.host_services += [{"name":"flutter","type":"mobile","preferred_port":0}]')
  SERVICES=$(echo "$SERVICES" | jq '.reasons += ["flutter: Flutter SDK and device emulator require host — API backend can be Dockerized"]')
fi

# GPU/CUDA detection
if find . -maxdepth 1 -name "*.cu" 2>/dev/null | head -1 | grep -q . || grep -rqE "torch|tensorflow|cuda" requirements.txt 2>/dev/null; then
  if ! docker info 2>/dev/null | grep -qi "nvidia\|gpu"; then
    SERVICES=$(echo "$SERVICES" | jq '.host_services += [{"name":"ml-gpu","type":"compute","preferred_port":0}]')
    SERVICES=$(echo "$SERVICES" | jq '.reasons += ["ml-gpu: NVIDIA Container Toolkit not detected — GPU workloads will run on host. Install nvidia-container-toolkit for Docker GPU support."]')
  fi
fi

# === OUTPUT ===
echo "$SERVICES" | jq '.'
